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

    /// Decoded graph per source (M13-1 sidebar trunks). Play pushes the
    /// decoded graph after a load/build; Chrome only reads it. Negative
    /// lookups are never cached, so a later build can make it appear.
    private(set) var graphs: [SourceID: Graph] = [:]

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

    // MARK: - GitHub sync (M15 Remote mailbox)

    /// In-flight syncs by source id (one per source; the engine slot is
    /// untouched — git is a settings-adjacent one-shot like clone).
    private var activeSyncSessions: [SourceID: SyncSession] = [:]

    /// Remote mailbox Sync verb: `fetch` + `pull --ff-only` through the
    /// credential helper, off the main actor. Marks the source syncing,
    /// updates branch / lastSyncError / lastSyncedAt on completion. The
    /// caller (RemoteMailboxView) suspends watch around the call — the
    /// working copy is the tree watch serves.
    func syncGithub(_ id: SourceID) async {
        guard let index = sources.firstIndex(where: { $0.id == id }),
              case .github(let github) = sources[index],
              github.isAvailable,
              let url = try? github.workspaceRoot()
        else { return }

        var syncing = github
        syncing.isSyncing = true
        syncing.lastSyncError = nil
        sources[index] = .github(syncing)

        let helperApp = Bundle.main.executableURL
        let session = SyncSession()
        activeSyncSessions[id] = session
        defer { activeSyncSessions[id] = nil }

        let result = await Task.detached {
            GithubSync.sync(workingCopy: url, credentialHelperApp: helperApp, session: session)
        }.value

        guard let index = sources.firstIndex(where: { $0.id == id }),
              case .github(let current) = sources[index]
        else { return }
        var updated = current
        updated.isSyncing = false
        if result.isSuccess {
            updated.lastSyncError = nil
            updated.lastSyncedAt = Date()
        } else {
            updated.lastSyncError = "git sync failed (exit \(result.exitCode)): \(result.stderr)"
        }
        updated.branch = GitClone.branchStatus(at: url).branch
        sources[index] = .github(updated)
    }

    /// SIGTERM the in-flight sync for a source. The working copy is left
    /// in place mid-pull; the next Sync retries.
    func cancelSyncGithub(_ id: SourceID) {
        activeSyncSessions[id]?.terminate()
    }

    // MARK: - GitHub commit (M16-1)

    /// In-flight commits by source id (same one-shot shape as sync).
    private var activeCommitSessions: [SourceID: SyncSession] = [:]

    /// Commit verb (M16-1): stage exactly the picked paths + commit, off
    /// the main actor, one-shots sharing a `SyncSession`. Watch is NOT
    /// suspended — commit touches only `.git`/the index, never the
    /// content tree watch serves (design §2). On success the branch
    /// refreshes (ahead grows by 1). Git's exit + stderr surface
    /// verbatim on failure (D11) — including the missing-identity error,
    /// which is never papered over.
    func commitGithub(
        _ id: SourceID,
        paths: [String],
        message: String
    ) async -> GithubCommit.CommitResult {
        guard let index = sources.firstIndex(where: { $0.id == id }),
              case .github(let github) = sources[index],
              github.isAvailable,
              let url = try? github.workspaceRoot()
        else {
            return GithubCommit.CommitResult(exitCode: 1, stderr: "Working copy is unavailable.")
        }

        let session = SyncSession()
        activeCommitSessions[id] = session
        defer { activeCommitSessions[id] = nil }

        let result = await Task.detached {
            GithubCommit.commit(
                paths: paths,
                message: message,
                workingCopy: url,
                session: session
            )
        }.value

        // Refresh the branch regardless of outcome — a failed commit can
        // still leave the index moved; the picker re-reads status anyway.
        if let index = sources.firstIndex(where: { $0.id == id }),
           case .github(let current) = sources[index]
        {
            var updated = current
            updated.branch = GitClone.branchStatus(at: url).branch
            sources[index] = .github(updated)
        }
        return result
    }

    /// SIGTERM the in-flight commit for a source. The index is left as
    /// the interrupted `git` left it; the next picker run re-reads it.
    func cancelCommitGithub(_ id: SourceID) {
        activeCommitSessions[id]?.terminate()
    }

    // MARK: - GitHub push (M16-2)

    /// In-flight pushes by source id (one-shot shape, engine slot untouched).
    private var activePushSessions: [SourceID: SyncSession] = [:]

    /// Push verb (M16-2): `git push -u origin <branch>` through the
    /// credential helper, off the main actor. Watch is NOT suspended
    /// (push touches only the remote + tracking refs, never the content
    /// tree watch serves — design §2). On success: ahead → 0 (branch
    /// refresh) and `lastPushedAt` set. Git's exit + stderr surface
    /// verbatim — 401/403 is the M15 §10 `needsAuth` posture,
    /// non-blocking, re-auth via the existing settings flow.
    func pushGithub(_ id: SourceID) async -> GithubCommit.CommitResult {
        guard let index = sources.firstIndex(where: { $0.id == id }),
              case .github(let github) = sources[index],
              github.isAvailable,
              let url = try? github.workspaceRoot()
        else {
            return GithubCommit.CommitResult(exitCode: 1, stderr: "Working copy is unavailable.")
        }
        let branch = GitClone.branchStatus(at: url).branch ?? github.branch ?? github.defaultBranch
        guard !branch.isEmpty else {
            return GithubCommit.CommitResult(exitCode: 1, stderr: "No branch to push.")
        }

        let session = SyncSession()
        activePushSessions[id] = session
        defer { activePushSessions[id] = nil }

        let helperApp = Bundle.main.executableURL
        let result = await Task.detached {
            GithubCommit.push(
                branch: branch,
                workingCopy: url,
                credentialHelperApp: helperApp,
                session: session
            )
        }.value

        // Refresh branch (ahead → 0 on success) and record lastPushedAt.
        if let index = sources.firstIndex(where: { $0.id == id }),
           case .github(let current) = sources[index]
        {
            var updated = current
            updated.branch = GitClone.branchStatus(at: url).branch
            if result.isSuccess {
                updated.lastPushedAt = Date()
            }
            sources[index] = .github(updated)
        }
        return result
    }

    /// SIGTERM the in-flight push for a source.
    func cancelPushGithub(_ id: SourceID) {
        activePushSessions[id]?.terminate()
    }

    // MARK: - GitHub sign-out (M15)

    /// Sign out of a GitHub source (design §4): delete the Keychain
    /// token — the only deletion path for it, plain `remove` never
    /// touches the token — then drop the source from the sidebar.
    /// `deleteWorkingCopy` additionally moves the user-owned working
    /// copy folder to the Trash; it is never deleted without the
    /// caller's explicit choice. A token-delete failure aborts the
    /// sign-out (the source stays); a Trash failure surfaces on
    /// `lastError` after the sign-out completes.
    func signOutGithub(_ id: SourceID, deleteWorkingCopy: Bool) {
        lastError = nil
        guard let index = sources.firstIndex(where: { $0.id == id }),
              case .github = sources[index]
        else { return }
        do {
            try GithubTokenStore().delete()
        } catch {
            lastError = "Sign out failed — the GitHub token could not be removed: \(String(describing: error))"
            return
        }
        if deleteWorkingCopy, let url = scopedURLs[id] {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                lastError = "Signed out, but the working copy could not be moved to the Trash: \(String(describing: error))"
            }
        }
        remove(id)
    }

    // MARK: - Graph mirror (M13-1)

    /// Sidebar read path for trunk folders. Cached value wins; otherwise
    /// decode `<root>/.boris/graph.json` lazily. Chrome never parses JSON
    /// itself — this is the store's mirror.
    func graph(for id: SourceID) -> Graph? {
        if let cached = graphs[id] { return cached }
        guard let url = resolvedURL(for: id) else { return nil }
        let fileURL = url
            .appendingPathComponent(".boris", isDirectory: true)
            .appendingPathComponent("graph.json")
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(Graph.self, from: data)
        else { return nil }
        graphs[id] = decoded
        return decoded
    }

    /// Play pushes the graph it already decoded after a load/build so
    /// the sidebar stays fresh without re-parsing JSON.
    func updateGraph(_ graph: Graph, for id: SourceID) {
        graphs[id] = graph
    }

    private func resolvedURL(for id: SourceID) -> URL? {
        if let url = scopedURLs[id] { return url }
        guard let item = sources.first(where: { $0.id == id }) else { return nil }
        switch item {
        case .local(let local):
            guard let resolved = try? local.resolve().url else { return nil }
            return resolved.standardizedFileURL
        case .github(let github):
            guard let resolved = try? github.resolve().url else { return nil }
            return resolved.standardizedFileURL
        }
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

    /// Add an authenticated GitHub source (M15): the working copy was
    /// already cloned by the sheet; here it is bookmarked like any
    /// folder and the identity is attached. The token was saved to the
    /// Keychain by the sheet under the same owner/repo.
    @discardableResult
    func addGithub(
        workingCopy url: URL,
        owner: String,
        repository: String,
        defaultBranch: String,
        grantedScopes: [String]
    ) -> GithubSource? {
        lastError = nil
        let standardized = url.standardizedFileURL
        do {
            var github = try GithubSource.make(
                workingCopy: standardized,
                owner: owner,
                repository: repository,
                defaultBranch: defaultBranch,
                grantedScopes: grantedScopes
            )
            github = beginAccess(github)
            sources.append(.github(github))
            select(github.id)
            noteRecent(standardized)
            persist()
            return github
        } catch {
            lastError = String(describing: error)
            return nil
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
            endAccess(id)
            if let index = sources.firstIndex(where: { $0.id == id }),
               case .github(let github) = sources[index]
            {
                var next = try GithubSource.make(
                    workingCopy: standardized,
                    owner: github.owner,
                    repository: github.repository,
                    defaultBranch: github.defaultBranch,
                    grantedScopes: github.grantedScopes
                )
                next.id = id
                next = beginAccess(next)
                sources[index] = .github(next)
            } else {
                var local = try LocalSource.make(from: standardized)
                local.id = id
                local = beginAccess(local)
                if let index = sources.firstIndex(where: { $0.id == id }) {
                    sources[index] = .local(local)
                } else {
                    sources.append(.local(local))
                }
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
        let githubs: [GithubSource] = sources.compactMap { item in
            if case .github(let github) = item { return github }
            return nil
        }
        let payload = PersistedWorkspace(
            sources: locals,
            selected: selection.sourceID,
            mailbox: selection.mailbox,
            github: githubs
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
            sources += payload.github.map { raw in
                var github = beginAccess(raw)
                if github.isAvailable, github.bookmarkData != raw.bookmarkData {
                    refreshed = true
                }
                return .github(github)
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
            // One porcelain read per add/load; nil for non-repos. Never
            // surfaced as an error — not-a-repo is a normal folder.
            local.branch = GitClone.currentBranch(at: resolved.url)
        } catch {
            local.isAvailable = false
        }
        return local
    }

    /// GitHub working-copy variant: resolve the bookmark, start access,
    /// refresh a stale bookmark, read the branch. Same failure posture
    /// as the local path — unavailable badge, no `lastError`.
    private func beginAccess(_ source: GithubSource) -> GithubSource {
        var github = source
        do {
            let resolved = try github.resolve()
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: resolved.url.path,
                isDirectory: &isDirectory
            ) && isDirectory.boolValue
            guard exists, resolved.url.startAccessingSecurityScopedResource() else {
                github.isAvailable = false
                return github
            }
            scopedURLs[github.id] = resolved.url
            github.displayPath = resolved.url.standardizedFileURL.path
            github.title = "\(github.owner)/\(github.repository)"
            github.isAvailable = true
            if resolved.stale, let refreshed = try? github.refreshedBookmark() {
                github.bookmarkData = refreshed.bookmarkData
            }
            github.branch = GitClone.currentBranch(at: resolved.url)
        } catch {
            github.isAvailable = false
        }
        return github
    }

    private func endAccess(_ id: SourceID) {
        if let url = scopedURLs.removeValue(forKey: id) {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
