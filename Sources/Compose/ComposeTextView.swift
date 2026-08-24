import AppKit
import SwiftUI

/// NSTextView host with live heuristic highlighting and native Find bar.
/// The text storage is re-painted after every edit; the buffer in
/// `ComposeDocument` stays the single source of truth.
///
/// Find & Replace (#225) uses the system find bar (`usesFindBar = true`,
/// `isIncrementalSearchingEnabled = true`) hosted in the enclosing
/// `NSScrollView` (which conforms to `NSTextFinderBarContainer`). This gives
/// ⌘F / ⌘⌥F / ⌘G / ⇧⌘G, wrap-around, case-insensitive and regex toggles for
/// free — no custom UI.
struct ComposeTextView: NSViewRepresentable {
    @Bindable var document: ComposeDocument
    /// Click-to-line target (LATER-3.1); nil = no pending jump.
    var jumpToCharacter: Int?
    /// Cooklang completion vocabulary (LATER-3.4); `.empty` disables the
    /// popup. Sourced from the selected source's `.boris/` artifacts.
    var completion: ComposeCookCompletion = .empty
    /// #238: Go to Line — 1-based line number to jump to; nil = no pending jump.
    var jumpToLine: Int?
    /// #263: toolbar-to-coordinator seam; the editor view owns the bus and
    /// the coordinator registers its applier on it.
    var formatApplier: ComposeFormatApplier?
    /// #264: reading-comfort ladder size (11…21, default 13). The editor
    /// view reads the observable's scalars so SwiftUI re-syncs on change.
    var fontSize: CGFloat = 13
    /// #264: gutter visibility from `ComposeTypography`.
    var showsLineNumbers: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document, completion: completion)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.findBarPosition = .aboveContent

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        context.coordinator.fontSize = fontSize
        textView.font = context.coordinator.currentFont
        // #264: breathing room — vertical inset + paragraph line spacing.
        textView.textContainerInset = NSSize(width: 10, height: 14)
        textView.defaultParagraphStyle = context.coordinator.paragraphStyle
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        // #225 Find & Replace: system find bar + incremental search.
        textView.usesFindBar = true
        textView.usesFindPanel = false
        textView.isIncrementalSearchingEnabled = true

        let gutter = makeGutter(for: textView)
        textView.addSubview(gutter)
        context.coordinator.gutter = gutter

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.hostedTextView = textView
        context.coordinator.scrollView = scrollView
        registerFormatApplier(context.coordinator)

        context.coordinator.applyHighlight(
            textView,
            text: document.text,
            language: document.language,
            force: true
        )
        // Gutter width tracks line count; update after initial paint.
        context.coordinator.updateGutterWidth()
        context.coordinator.applyGutterVisibility()
        gutter.needsDisplay = true
        document.updateCursor(textView.selectedRange())
        return scrollView
    }

    /// #226 Line numbers gutter: lightweight overlay as subview of the
    /// textView so it scrolls vertically with the buffer but stays fixed
    /// horizontally (widthTracksTextView disables horizontal scroll).
    private func makeGutter(for textView: NSTextView) -> ComposeLineGutter {
        let gutter = ComposeLineGutter()
        gutter.textView = textView
        gutter.frame = NSRect(x: 0, y: 0, width: 36, height: textView.bounds.height)
        gutter.autoresizingMask = [.height]
        gutter.wantsLayer = true
        // Reserve 36pt for the gutter + keep 10pt original inset as gap.
        textView.textContainer?.lineFragmentPadding = 36
        return gutter
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.document = document
        context.coordinator.completion = completion
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        registerFormatApplier(context.coordinator)
        // #264: reading-comfort syncs (font ladder + gutter visibility).
        context.coordinator.setFontSize(fontSize)
        context.coordinator.showsLineNumbers = showsLineNumbers
        // Re-bind gutter if view was recreated (SwiftUI .id)
        if let gutter = context.coordinator.gutter, gutter.superview !== textView {
            gutter.textView = textView
            gutter.frame = NSRect(x: 0, y: 0, width: gutter.frame.width, height: textView.bounds.height)
            textView.addSubview(gutter)
        }

        // Page switch (#225 edge): the buffer was replaced wholesale. Hide the
        // find bar so it does not survive across pages. The SwiftUI `.id`
        // recreation in `ComposeEditorView` is the primary reset; this is the
        // fallback when the view is reused.
        if textView.string != document.text {
            // Best-effort hide via NSTextFinderBarContainer. NSScrollView
            // conforms to it in AppKit, even though the header only exposes
            // `findBarPosition`; the `findBarVisible` selector is available
            // at runtime.
            if scrollView.responds(to: Selector(("setFindBarVisible:"))) {
                scrollView.perform(Selector(("setFindBarVisible:")), with: NSNumber(value: false))
            }
            textView.string = document.text
            context.coordinator.applyHighlight(textView, text: document.text, language: document.language, force: true)
        } else {
            context.coordinator.applyHighlight(textView, text: document.text, language: document.language)
        }
        context.coordinator.jump(to: jumpToCharacter, in: textView)
        if let jumpToLine {
            context.coordinator.jumpToLine(jumpToLine)
        }
        document.updateCursor(textView.selectedRange())
        context.coordinator.updateGutterWidth()
        context.coordinator.applyGutterVisibility()
        // Keep gutter height in sync with textView content height
        if let gutter = context.coordinator.gutter {
            var gutterFrame = gutter.frame
            gutterFrame.size.height = max(textView.bounds.height, scrollView.contentSize.height)
            gutter.frame = gutterFrame
            gutter.needsDisplay = true
        }
    }

    /// #263: point the toolbar bus at this coordinator (weakly — the bus is
    /// owned by the SwiftUI view and outlives view rebuilds).
    private func registerFormatApplier(_ coordinator: Coordinator) {
        guard let formatApplier else { return }
        formatApplier.handler = { [weak coordinator] format in
            coordinator?.apply(format)
        }
    }
}
