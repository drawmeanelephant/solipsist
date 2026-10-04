import Foundation
import Observation

/// A buffer keeps its own bookmark access and resolved roots, even when
/// Settings relocates or removes the source that originally supplied it.
final class ComposeSourceBinding: Sendable {
    let source: LocalSource
    let workspaceRoot: URL
    let contentRoot: URL
    private let scopedURL: URL
    private let hasAccess: Bool

    init(source: LocalSource) throws {
        guard source.isAvailable else {
            throw CocoaError(.fileReadNoPermission)
        }
        let url = try source.resolve().url
        self.source = source
        self.scopedURL = url
        self.hasAccess = url.startAccessingSecurityScopedResource()
        self.workspaceRoot = url.standardizedFileURL
        self.contentRoot = LocalSource.isProjectRoot(workspaceRoot)
            ? workspaceRoot.appendingPathComponent("content", isDirectory: true)
            : workspaceRoot
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
        let source: LocalSource
        let selection: WorkspaceSelection
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
            let owner = try ComposeSourceBinding(source: request.source)
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
            loadError = String(describing: error)
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
            loadError = String(describing: error)
            return false
        }
    }
}
