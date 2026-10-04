import Foundation
import Observation

/// A buffer keeps its own bookmark access and resolved roots, even when
/// Settings relocates or removes the source that originally supplied it.
final class ComposeSourceBinding: Sendable {
    let source: any PlayFolderSource
    let workspaceRoot: URL
    let contentRoot: URL
    private let scopedURL: URL
    private let hasAccess: Bool

    enum AccessError: LocalizedError {
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let title):
                return "The working folder for “\(title)” is unavailable or unreadable. Relocate it in Settings → Sources."
            }
        }
    }

    init(source: any PlayFolderSource) throws {
        guard source.isAvailable else {
            throw AccessError.unavailable(source.title)
        }
        let url = try source.resolve().url
        let hasAccess = url.startAccessingSecurityScopedResource()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue, FileManager.default.isReadableFile(atPath: url.path)
        else {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
            throw AccessError.unavailable(source.title)
        }
        self.source = source
        self.scopedURL = url
        self.hasAccess = hasAccess
        self.workspaceRoot = url.standardizedFileURL
        self.contentRoot = source.contentRoot(in: workspaceRoot)
    }

    deinit {
        if hasAccess {
            scopedURL.stopAccessingSecurityScopedResource()
        }
    }

    func isWatched(sourceID: SourceID?, contentRoot: URL?) -> Bool {
        source.id == sourceID && self.contentRoot == contentRoot
    }
}

/// Selection and dirty-work transitions shared by the native window and
/// headless regressions. Failed resolution/load never replaces the buffer.
@MainActor
@Observable
final class ComposeBuffer {
    struct Request: Hashable {
        let source: SourceItem
        let selection: WorkspaceSelection

        init(source: SourceItem, selection: WorkspaceSelection) {
            self.source = source
            self.selection = selection
        }

        init(source: LocalSource, selection: WorkspaceSelection) {
            self.init(source: .local(source), selection: selection)
        }

        init(source: GithubSource, selection: WorkspaceSelection) {
            self.init(source: .github(source), selection: selection)
        }
    }

    struct Page {
        let owner: ComposeSourceBinding
        let selection: WorkspaceSelection
        let noun: WorkspaceNoun
        let fileURL: URL

        func isSameFile(as other: Page) -> Bool {
            owner.source.id == other.owner.source.id
                && owner.workspaceRoot == other.owner.workspaceRoot
                && noun.id == other.noun.id
                && fileURL == other.fileURL
        }
    }

    private(set) var document = ComposeDocument()
    private(set) var page: Page?
    private(set) var pendingPage: Page?
    private(set) var loadError: String?

    /// Resolve before asking to discard, and commit the binding only after
    /// the new file has been read successfully.
    @discardableResult
    func select(_ request: Request?) -> Bool {
        pendingPage = nil
        guard let request, let noun = request.selection.noun, noun.kind == "page",
              request.selection.sourceID == request.source.id
        else { return false }
        do {
            let owner = try ComposeSourceBinding(source: request.source.folderSource)
            guard let node = try ComposePageResolver.page(id: noun.id, workspaceRoot: owner.workspaceRoot) else {
                loadError = "No graph node for “\(noun.title)”."
                return false
            }
            let next = Page(
                owner: owner,
                selection: request.selection,
                noun: noun,
                fileURL: ComposePageResolver.fileURL(contentRoot: owner.contentRoot, sourcePath: node.sourcePath).standardizedFileURL
            )
            if let page, page.isSameFile(as: next) {
                loadError = nil
                return false
            }
            if document.isDirty {
                pendingPage = next
                return false
            }
            return load(next)
        } catch {
            loadError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func discardAndSwitch(to capturedPage: Page? = nil) -> Bool {
        guard let next = capturedPage ?? pendingPage else { return false }
        pendingPage = nil
        return load(next)
    }

    /// Save still owns the OLD page here. A failed/cancelled save must not
    /// accept the pending switch or discard the author's text.
    @discardableResult
    func saveAndSwitch(to capturedPage: Page? = nil, save: () -> Bool) -> Bool {
        guard let next = capturedPage ?? pendingPage, save() else { return false }
        return discardAndSwitch(to: next)
    }

    func cancelSwitch() {
        pendingPage = nil
    }

    func stage(_ draft: StagedPostDraft) {
        document = ComposeDocument()
        document.text = PostDraftAssembly.markdown(for: draft)
        page = nil
        pendingPage = nil
        loadError = nil
    }

    private func load(_ next: Page) -> Bool {
        do {
            try document.load(from: next.fileURL)
            page = next
            loadError = nil
            return true
        } catch {
            loadError = error.localizedDescription
            return false
        }
    }
}
