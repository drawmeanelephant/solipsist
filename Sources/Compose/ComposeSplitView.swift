import AppKit
import SwiftUI

/// Helper that configures the underlying `NSSplitView` backing a SwiftUI
/// `HSplitView` (#227). It sets a visible divider (`dividerStyle = .thin`),
/// an `autosaveName` so the split ratio persists, and enforces minimum pane
/// widths (frontmatter 230, editor 280, preview 240).
///
/// macOS 27 note: the backing split view is managed by an internal
/// SplitViewController, whose delegate can no longer be modified — AppKit
/// throws `NSInternalInconsistencyException`. Minimums are therefore
/// enforced with per-pane width constraints, not delegate callbacks.
///
/// Usage: attach as a background to any pane inside the `HSplitView`:
///
///     HSplitView { ... }
///       .background(SplitViewAutosave(name: autosaveName, showFrontmatter: ..., showPreview: ...))
///
/// The helper walks up the view hierarchy to find the `NSSplitView` and
/// configures it. It stays lightweight — no custom drag handle, no third-party
/// library.
struct SplitViewAutosave: NSViewRepresentable {
    var name: String
    var showFrontmatter: Bool
    var showPreview: Bool

    func makeNSView(context: Context) -> AutosaveHelperView {
        let view = AutosaveHelperView()
        view.autosaveName = name
        view.showFrontmatter = showFrontmatter
        view.showPreview = showPreview
        return view
    }

    func updateNSView(_ nsView: AutosaveHelperView, context: Context) {
        nsView.autosaveName = name
        nsView.showFrontmatter = showFrontmatter
        nsView.showPreview = showPreview
        nsView.configureIfNeeded()
    }

    final class AutosaveHelperView: NSView {
        var autosaveName: String = "" {
            didSet { configureIfNeeded() }
        }

        var showFrontmatter: Bool = false {
            didSet { configureIfNeeded() }
        }

        var showPreview: Bool = true {
            didSet { configureIfNeeded() }
        }

        private weak var splitView: NSSplitView?
        private var widthConstraints: [NSLayoutConstraint] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { self.configureIfNeeded() }
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            DispatchQueue.main.async { self.configureIfNeeded() }
        }

        func configureIfNeeded() {
            guard let splitView = findSplitView() else { return }
            // Avoid re-assigning the same configuration repeatedly
            if splitView.autosaveName != autosaveName {
                splitView.autosaveName = autosaveName
            }
            if splitView.dividerStyle != .thin {
                splitView.dividerStyle = .thin
            }
            applyMinimumWidths(to: splitView)
            self.splitView = splitView
        }

        /// Same minimums the old delegate callbacks enforced, expressed as
        /// layout constraints. Sub-999 priority so a window narrower than
        /// the sum of minimums degrades gracefully instead of throwing
        /// unsatisfiable-constraint diagnostics.
        private func applyMinimumWidths(to splitView: NSSplitView) {
            for constraint in widthConstraints {
                constraint.isActive = false
            }
            widthConstraints.removeAll()
            let mins = minWidths(for: splitView)
            for (pane, minimum) in zip(splitView.subviews, mins) {
                let constraint = pane.widthAnchor.constraint(
                    greaterThanOrEqualToConstant: minimum
                )
                constraint.priority = NSLayoutConstraint.Priority(999)
                constraint.isActive = true
                widthConstraints.append(constraint)
            }
        }

        private func findSplitView() -> NSSplitView? {
            // Walk up from helper's superview chain
            var parent = superview
            while let current = parent {
                if let split = current as? NSSplitView { return split }
                parent = current.superview
            }
            // Fallback: search window's view hierarchy for an NSSplitView that
            // contains this helper as a descendant
            guard let window, let contentView = window.contentView else { return nil }
            return searchSplitView(in: contentView)
        }

        private func searchSplitView(in view: NSView) -> NSSplitView? {
            if let split = view as? NSSplitView, isDescendant(of: view) {
                return split
            }
            for subview in view.subviews {
                if let found = searchSplitView(in: subview) { return found }
            }
            return nil
        }

        private func minWidths(for splitView: NSSplitView) -> [CGFloat] {
            let count = splitView.subviews.count
            // Map based on showFrontmatter/showPreview state we were configured with
            // The subviews order matches the HSplitView builder order
            switch count {
            case 1:
                return [280] // editor only
            case 2:
                if showFrontmatter, !showPreview {
                    return [230, 280] // frontmatter + editor
                } else {
                    // editor + preview (frontmatter off, preview on) or any other 2-pane
                    return [280, 240]
                }
            case 3:
                return [230, 280, 240] // frontmatter + editor + preview
            default:
                return Array(repeating: 200, count: count)
            }
        }
    }
}
