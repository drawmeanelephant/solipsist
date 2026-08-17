import AppKit
import Foundation
import Observation

/// One observable store for the source list and the current selection.
/// Play, inspector, and companions read this; they do not keep their own copy.
@MainActor
@Observable
final class WorkspaceStore {
    private static let persistenceKey = "solipsist.workspace.sources.v1"

    private(set) var sources: [SourceItem] = []
    var selection: WorkspaceSelection = .empty
    /// Surfaced, never swallowed. Cleared on the next successful action.
    var lastError: String?

    /// URLs we have called `startAccessingSecurityScopedResource` on.
    @ObservationIgnored
    private var scopedURLs: [SourceID: URL] = [:]

    init() {
        load()
    }

    var selectedSource: SourceItem? {
        guard let id = selection.sourceID else { return nil }
        return sources.first { $0.id == id }
    }

    func select(_ id: SourceID?) {
        guard selection.sourceID != id else { return }
        selection.sourceID = id
        selection.noun = nil
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
            persist()
        } catch {
            lastError = String(describing: error)
        }
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
            selected: selection.sourceID
        )
        do {
            let data = try JSONEncoder().encode(payload)
            UserDefaults.standard.set(data, forKey: Self.persistenceKey)
        } catch {
            lastError = String(describing: error)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.persistenceKey) else {
            return
        }
        do {
            let payload = try JSONDecoder().decode(PersistedWorkspace.self, from: data)
            sources = payload.sources.map { raw in
                var local = raw
                local = beginAccess(local)
                return .local(local)
            }
            if let selected = payload.selected,
               sources.contains(where: { $0.id == selected })
            {
                selection.sourceID = selected
            }
        } catch {
            lastError = String(describing: error)
        }
    }

    // MARK: - Sandbox access

    private func beginAccess(_ source: LocalSource) -> LocalSource {
        var local = source
        do {
            let resolved = try local.resolve()
            guard resolved.url.startAccessingSecurityScopedResource() else {
                local.isAvailable = false
                lastError = "Could not access \(local.displayPath)"
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
            lastError = String(describing: error)
        }
        return local
    }

    private func endAccess(_ id: SourceID) {
        if let url = scopedURLs.removeValue(forKey: id) {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

private struct PersistedWorkspace: Codable {
    var sources: [LocalSource]
    var selected: SourceID?
}
