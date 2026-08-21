import AppKit
import SwiftUI

/// Helper that configures the underlying `NSSplitView` backing a SwiftUI
/// `HSplitView` (#227). It sets a visible divider (`dividerStyle = .thin`),
/// an `autosaveName` so the split ratio persists, and enforces minimum pane
/// widths (frontmatter 230, editor 280, preview 240). It also keeps the
/// divider keyboard-accessible (NSSplitView does this natively).
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

    final class AutosaveHelperView: NSView, NSSplitViewDelegate {
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
            if splitView.delegate !== self {
                splitView.delegate = self
            }
            self.splitView = splitView
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

        // MARK: NSSplitViewDelegate — enforce minimum widths

        func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
            false
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMinCoordinate proposedMinimumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            let mins = minWidths(for: splitView)
            let thickness = splitView.dividerThickness
            let totalWidth = splitView.bounds.width
            let count = splitView.subviews.count
            guard dividerIndex < count - 1, mins.count == count else { return proposedMinimumPosition }

            // Minimum for this divider = sum of mins up to dividerIndex + thickness * dividerIndex
            var minPos: CGFloat = 0
            for idx in 0...dividerIndex {
                minPos += mins[idx]
                if idx < dividerIndex { minPos += thickness }
            }
            // Also need to include thickness for the divider itself? The
            // divider's coordinate is its origin, so min is sum of previous pane widths + thicknesses
            // For divider 0, min = mins[0]
            // For divider 1, min = mins[0] + thickness + mins[1]
            // Our loop above already does that if we include thickness for idx < dividerIndex
            // For divider 0, loop 0...0 => min = mins[0]
            // For divider 1, loop 0...1 => min = mins[0] + mins[1] + thickness
            return max(proposedMinimumPosition, minPos)
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMaxCoordinate proposedMaximumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            let mins = minWidths(for: splitView)
            let thickness = splitView.dividerThickness
            let totalWidth = splitView.bounds.width
            let count = splitView.subviews.count
            guard dividerIndex < count - 1, mins.count == count else { return proposedMaximumPosition }

            // Maximum for this divider = totalWidth - sum of mins after divider - thickness for remaining dividers
            var remainingMins: CGFloat = 0
            for idx in (dividerIndex + 1)..<count {
                remainingMins += mins[idx]
            }
            let remainingDividers = count - dividerIndex - 2 // dividers after this one
            let maxPos = totalWidth - remainingMins - CGFloat(max(0, remainingDividers)) * thickness - thickness
            // For divider 0 with 3 panes: max = total - mins[1] - mins[2] - 2*thickness
            // For divider 1 with 3 panes: max = total - mins[2] - thickness
            // For divider 0 with 2 panes: max = total - mins[1] - thickness
            return min(proposedMaximumPosition, maxPos)
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
