import AppKit
import Foundation
import Observation

/// One observable store for the source list and the current selection.
/// Play, inspector, and companions read this; they do not keep their own copy.
@MainActor
@Observable
final class WorkspaceStore {
    private let defaults: UserDefaults

    private(set) var sources: [SourceItem] = []
    private(set) var recentFolderURLs: [URL] = []
    var selection: WorkspaceSelection = .empty
    /// Surfaced, never swallowed. Cleared on the next successful action.
    /// Stale sources do not write this — the sidebar badge is the warning.
    var lastError: String?

    /// URLs we have called `startAccessingSecurityScopedResource` on.
    @ObservationIgnored
    private var scopedURLs: [SourceID: URL] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        refreshRecentFolders()
    }

    var selectedSource: SourceItem? {
        guard let id = selection.sourceID else { return nil }
        return sources.first { $0.id == id }
    }

    func select(_ id: SourceID?) {
        let next = WorkspaceSelectionRules.selectSource(selection, id: id)
        guard next != selection else { return }
        selection = next
        persist()
    }

    func select(mailbox: String) {
        let next = WorkspaceSelectionRules.selectMailbox(selection, mailbox: mailbox)
        guard next != selection else { return }
        selection = next
        persist()
    }

    /// Sidebar write path. Header click passes `mailbox: WorkspaceMailbox.pages`.
    func select(_ id: SourceID, mailbox: String) {
        let next = WorkspaceSelectionRules.select(selection, id: id, mailbox: mailbox)
        guard next != selection else { return }
        selection = next
        persist()
    }

    func select(noun: WorkspaceNoun?) {
        selection.noun = noun
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Open"
        panel.message = "Choose a local folder to add as a source."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addLocal(url: url)
    }

    func presentNewProjectPanel(runtime: AppRuntime) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Create Project"
        panel.message = "Choose a folder to initialize a new Boris project."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let engine = runtime.engine else {
            lastError = runtime.engineError ?? "Engine not found."
            return
        }

        Task {
            do {
                let result = try await engine.initProject(in: url)
                if result.exitCode == 0 {
                    self.addLocal(url: url)
                } else {
                    self.lastError = "boris init failed (exit \(result.exitCode)): \(result.stderr)"
                }
            } catch {
                self.lastError = String(describing: error)
            }
        }
    }

    // MARK: - Git clone (M12 / #131)

    /// True while a `git clone` is in flight; the Settings pane shows a
    /// cancel affordance off this.
    private(set) var isCloning = false
    private var activeCloneSession: CloneSession?

    /// Settings + File menu entry point. Prompts for a clone URL, then a
    /// destination parent folder, then clones and adds the result as a
    /// Local source through the same store Open… writes.
    func presentClonePanel() {
        let alert = NSAlert()
        alert.messageText = "Add Git Repository"
        alert.informativeText = "Enter a clone URL. The repository will be cloned into the folder you choose and added as a Local source."
        alert.addButton(withTitle: "Clone")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "https://github.com/user/repo.git"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let urlString = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GitClone.isValidCloneURL(urlString) else {
            lastError = "Not a git clone URL: \(urlString)"
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Clone Into"
        panel.message = "Choose a parent folder. \(GitClone.repoName(from: urlString)) will be created inside it."
        guard panel.runModal() == .OK, let parent = panel.url else { return }

        let dest = parent.appendingPathComponent(GitClone.repoName(from: urlString), isDirectory: true)
        cloneRepository(urlString: urlString, to: dest)
    }

    /// Runs `/usr/bin/git clone -- <url> <dest>` off the main actor, then
    /// either adds the folder via `addLocal` (same store as Open…) or
    /// surfaces git's exit + stderr on `lastError`. Cancel = SIGTERM.
    func cloneRepository(urlString: String, to dest: URL) {
        lastError = nil
        isCloning = true
        let session = CloneSession()
        activeCloneSession = session
        Task.detached { [weak self] in
            let result: GitClone.CloneResult
            do {
                result = try GitClone.clone(url: urlString, to: dest, session: session)
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.isCloning = false
                    self.activeCloneSession = nil
                    self.lastError = "git clone failed: \(String(describing: error))"
                }
                return
            }
            await MainActor.run {
                guard let self else { return }
                self.isCloning = false
                self.activeCloneSession = nil
                if result.isSuccess {
                    self.addLocal(url: dest)
                } else {
                    self.lastError = "git clone failed (exit \(result.exitCode)): \(result.stderr)"
                }
            }
        }
    }

    /// SIGTERM the in-flight clone. The cloned directory (if any) is left
    /// in place; nothing is added to the source list.
    func cancelClone() {
        activeCloneSession?.terminate()
    }

    func addLocal(url: URL) {
        lastError = nil
        let standardized = url.standardizedFileURL
        if let existing = sources.first(where: { item in
            if case .local(let local) = item {
                return local.displayPath == standardized.path
            }
            return false
        }) {
            select(existing.id)
            return
        }

        do {
            var local = try LocalSource.make(from: standardized)
            local = beginAccess(local)
            sources.append(.local(local))
            select(local.id)
            noteRecent(standardized)
            persist()
        } catch {
            lastError = String(describing: error)
        }
    }

    func presentRelocatePanel(for id: SourceID) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Relocate"
        panel.message = "Choose the folder this source moved to."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        relocate(id, to: url)
    }

    func relocate(_ id: SourceID, to url: URL) {
        lastError = nil
        let standardized = url.standardizedFileURL
        if let existing = sources.first(where: { item in
            guard item.id != id, case .local(let local) = item else { return false }
            return local.displayPath == standardized.path
        }) {
            remove(id)
            select(existing.id)
            return
        }

        do {
            var local = try LocalSource.make(from: standardized)
            local.id = id
            endAccess(id)
            local = beginAccess(local)
            if let index = sources.firstIndex(where: { $0.id == id }) {
                sources[index] = .local(local)
            } else {
                sources.append(.local(local))
            }
            select(id)
            noteRecent(standardized)
            persist()
        } catch {
            lastError = String(describing: error)
        }
    }

    func openFromSystem(_ url: URL) {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue
        {
            addLocal(url: url)
        } else {
            addLocal(url: url.deletingLastPathComponent())
        }
    }

    func clearRecentFolders() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        refreshRecentFolders()
    }

    func remove(_ id: SourceID) {
        lastError = nil
        endAccess(id)
        sources.removeAll { $0.id == id }
        if selection.sourceID == id {
            selection = .empty
            if let first = sources.first {
                select(first.id)
            }
        }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        let locals: [LocalSource] = sources.compactMap { item in
            if case .local(let local) = item { return local }
            return nil
        }
        let payload = PersistedWorkspace(
            sources: locals,
            selected: selection.sourceID,
            mailbox: selection.mailbox
        )
        do {
            defaults.set(try WorkspacePersistence.encode(payload), forKey: WorkspacePersistence.defaultsKey)
        } catch {
            lastError = String(describing: error)
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: WorkspacePersistence.defaultsKey) else {
            return
        }
        do {
            let payload = try WorkspacePersistence.decode(data)
            var refreshed = false
            sources = payload.sources.map { raw in
                var local = raw
                local = beginAccess(local)
                if local.isAvailable, local.bookmarkData != raw.bookmarkData {
                    refreshed = true
                }
                return .local(local)
            }
            selection = WorkspaceSelectionRules.restore(
                selected: payload.selected,
                mailbox: payload.mailbox,
                available: Set(sources.map(\.id))
            )
            if refreshed {
                persist()
            }
        } catch {
            lastError = String(describing: error)
        }
    }

    private func noteRecent(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        refreshRecentFolders()
    }

    func refreshRecentFolders() {
        recentFolderURLs = NSDocumentController.shared.recentDocumentURLs
    }

    // MARK: - Sandbox access

    /// Resolve + start access. Failures mark the source unavailable and do
    /// not write `lastError` — the sidebar badge is the non-blocking warning.
    private func beginAccess(_ source: LocalSource) -> LocalSource {
        var local = source
        do {
            let resolved = try local.resolve()
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: resolved.url.path,
                isDirectory: &isDirectory
            ) && isDirectory.boolValue
            guard exists, resolved.url.startAccessingSecurityScopedResource() else {
                local.isAvailable = false
                return local
            }
            scopedURLs[local.id] = resolved.url
            local.displayPath = resolved.url.standardizedFileURL.path
            local.title = resolved.url.lastPathComponent
            local.isAvailable = true
            if resolved.stale, let refreshed = try? local.refreshedBookmark() {
                local.bookmarkData = refreshed.bookmarkData
            }
        } catch {
            local.isAvailable = false
        }
        return local
    }

    private func endAccess(_ id: SourceID) {
        if let url = scopedURLs.removeValue(forKey: id) {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
