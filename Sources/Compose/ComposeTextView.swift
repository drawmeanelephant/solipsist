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
struct ComposeTextView: NSViewRepresentable { // swiftlint:disable:this type_body_length
    @Bindable var document: ComposeDocument
    /// Click-to-line target (LATER-3.1); nil = no pending jump.
    var jumpToCharacter: Int?
    /// Cooklang completion vocabulary (LATER-3.4); `.empty` disables the
    /// popup. Sourced from the selected source's `.boris/` artifacts.
    var completion: ComposeCookCompletion = .empty
    /// #238: Go to Line — 1-based line number to jump to; nil = no pending jump.
    var jumpToLine: Int?

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
        textView.font = baseFont
        textView.textContainerInset = NSSize(width: 10, height: 10)
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

        // #226 Line numbers gutter: lightweight overlay as subview of the
        // textView so it scrolls vertically with the buffer but stays fixed
        // horizontally (widthTracksTextView disables horizontal scroll).
        let gutter = ComposeLineGutter()
        gutter.textView = textView
        gutter.frame = NSRect(x: 0, y: 0, width: 36, height: textView.bounds.height)
        gutter.autoresizingMask = [.height]
        gutter.wantsLayer = true
        // Reserve 36pt for the gutter + keep 10pt original inset as gap.
        textView.textContainer?.lineFragmentPadding = 36
        textView.addSubview(gutter)
        context.coordinator.gutter = gutter

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.hostedTextView = textView
        context.coordinator.scrollView = scrollView

        context.coordinator.applyHighlight(
            textView,
            text: document.text,
            language: document.language,
            force: true
        )
        // Gutter width tracks line count; update after initial paint.
        context.coordinator.updateGutterWidth()
        gutter.needsDisplay = true
        document.updateCursor(textView.selectedRange())
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.document = document
        context.coordinator.completion = completion
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
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
        // Keep gutter height in sync with textView content height
        if let gutter = context.coordinator.gutter {
            var gutterFrame = gutter.frame
            gutterFrame.size.height = max(textView.bounds.height, scrollView.contentSize.height)
            gutter.frame = gutterFrame
            gutter.needsDisplay = true
        }
    }

    private var baseFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var document: ComposeDocument
        /// Cooklang completion vocabulary, updated on view syncs so a
        /// freshly-built `.boris/` index reaches the popup without a reload.
        var completion: ComposeCookCompletion = .empty
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        weak var gutter: ComposeLineGutter?
        private var isApplying = false
        /// Last click-to-line offset we applied, so re-syncs do not re-jump.
        private var lastJumpedCharacter: Int?
        /// #238: Weak reference to the hosted NSTextView, set once during
        /// `makeNSView` so `jumpToLine` can register undo and scroll.
        weak var hostedTextView: NSTextView?

        /// Last state we painted, so programmatic syncs (which fire on every
        /// `document` change) do not re-paint an unchanged buffer.
        private var lastHighlightedText: String?
        private var lastHighlightedLanguage: ComposeLanguage?

        init(document: ComposeDocument, completion: ComposeCookCompletion = .empty) {
            self.document = document
            self.completion = completion
        }

        func textDidChange(_ notification: Notification) {
            guard
                !isApplying,
                let textView = notification.object as? NSTextView
            else { return }
            isApplying = true
            defer { isApplying = false }

            let oldText = document.text
            let newText = textView.string
            document.text = newText
            repaintChanged(oldText: oldText, newText: newText, textView: textView, language: document.language)
            maybeOpenCompletion(in: textView, previousText: oldText)
            updateGutterWidth()
            gutter?.needsDisplay = true
            document.updateCursor(textView.selectedRange())
            // Keep gutter height in sync with textView's content height
            if let gutter {
                var gutterFrame = gutter.frame
                gutterFrame.size.height = max(textView.bounds.height, scrollView?.contentSize.height ?? 0)
                gutter.frame = gutterFrame
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                gutter?.needsDisplay = true
                return
            }
            gutter?.needsDisplay = true
            document.updateCursor(textView.selectedRange())
        }

        /// Update gutter width and text container padding when line count grows
        /// beyond 4 digits. Minimum 36pt.
        func updateGutterWidth() {
            guard let gutter, let textView else { return }
            let newWidth = gutter.gutterWidth
            if abs(gutter.frame.width - newWidth) > 0.5 {
                var gutterFrame = gutter.frame
                gutterFrame.size.width = newWidth
                gutter.frame = gutterFrame
                textView.textContainer?.lineFragmentPadding = newWidth
                textView.needsLayout = true
                gutter.needsDisplay = true
            }
        }

        /// LATER-3.4: when the author types a Cooklang token marker (`@`,
        /// `#`, `~`) in a Cooklang buffer with a corpus vocabulary, open the
        /// native completion popup. The popup is fed by
        /// `textView(_:completions:forPartialWordRange:indexOfSelectedItem:)`
        /// below; everything stays inside the single NSTextView surface.
        private func maybeOpenCompletion(in textView: NSTextView, previousText: String) {
            guard
                document.language == .cooklang,
                !completion.isEmpty,
                let inserted = CookMarkerScanner.insertedMarker(
                    from: previousText,
                    to: textView.string
                ),
                CookMarkerScanner.markers.contains(inserted)
            else { return }
            textView.complete(nil)
        }

        // MARK: NSTextView completion (LATER-3.4)

        func textView(
            _ textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            guard document.language == .cooklang, !completion.isEmpty else { return words }
            let text = textView.string as NSString
            guard
                charRange.location > 0,
                let marker = CookMarkerScanner.marker(
                    before: charRange.location,
                    in: text
                )
            else { return words }
            let prefix = text.substring(with: charRange)
            let suggestions = completion.suggestions(marker: marker, prefix: prefix)
            index?.pointee = 0
            return suggestions
        }

        /// Incremental repaint (LATER-3.2): restyle only the changed line(s)
        /// in place instead of replacing the whole storage, so a keystroke in
        /// a large buffer no longer repaints (and re-lays-out) off-screen
        /// text. Full paint still runs on load / language change / program-
        /// matic sync (`applyHighlight`).
        private func repaintChanged(
            oldText: String,
            newText: String,
            textView: NSTextView,
            language: ComposeLanguage
        ) {
            let change = ComposeHighlighter.changedRange(old: oldText, new: newText)
            let nsNew = newText as NSString
            let clampedLocation = min(max(change.location, 0), nsNew.length)
            let clampedLength = min(max(change.length, 1), nsNew.length - clampedLocation)
            // Expand to the full containing line(s) so `^`-anchored rules and
            // delimiters on the edited line restyle together.
            let target = nsNew.lineRange(
                for: NSRange(location: clampedLocation, length: clampedLength)
            )
            guard target.length > 0, let storage = textView.textStorage as? NSMutableAttributedString else {
                lastHighlightedText = newText
                lastHighlightedLanguage = language
                return
            }
            storage.beginEditing()
            ComposeHighlighter.repaint(newText, language: language, in: target, storage: storage)
            storage.endEditing()
            lastHighlightedText = newText
            lastHighlightedLanguage = language
        }

        func applyHighlight(_ textView: NSTextView, text: String, language: ComposeLanguage, force: Bool = false) {
            guard force || text != lastHighlightedText || language != lastHighlightedLanguage else { return }
            lastHighlightedText = text
            lastHighlightedLanguage = language

            let highlighted = ComposeHighlighter.highlight(text, language: language)
            textView.textStorage?.beginEditing()
            textView.textStorage?.setAttributedString(highlighted)
            textView.textStorage?.endEditing()
            textView.typingAttributes = [.font: baseFont, .foregroundColor: NSColor.labelColor]
        }

        /// Moves the selection to a character offset (click-to-line).
        /// Runs after highlight so the storage is current; clamps so a
        /// stale span can never exceed the buffer.
        func jump(to character: Int?, in textView: NSTextView) {
            guard let character, character != lastJumpedCharacter else { return }
            lastJumpedCharacter = character
            let nsString = textView.string as NSString
            let clamped = min(max(character, 0), nsString.length)
            let range = NSRange(location: clamped, length: 0)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
        }

        /// #238: Jump to a 1-based line number. Registers the current cursor
        /// position in the undo stack so ⌘Z restores it. Clamps to the
        /// buffer range; empty buffers jump to offset 0.
        func jumpToLine(_ line: Int) {
            guard let textView = hostedTextView else { return }
            let nsString = textView.string as NSString
            guard nsString.length > 0 else { return }
            let currentRange = textView.selectedRange()
            let undoManager = textView.undoManager
            undoManager?.registerUndo(withTarget: textView) { target in
                target.setSelectedRange(currentRange)
                target.scrollRangeToVisible(currentRange)
            }
            undoManager?.setActionName("Go to Line")
            let totalLines = max(1, nsString.components(separatedBy: "\n").count)
            let clamped = max(1, min(line, totalLines))
            var foundLine = 1
            var targetLocation = 0
            nsString.enumerateSubstrings(
                in: NSRange(location: 0, length: nsString.length),
                options: [.byLines, .substringNotRequired]
            ) { _, range, _, stop in
                if foundLine == clamped {
                    targetLocation = range.location
                    stop.pointee = true
                }
                foundLine += 1
            }
            let range = NSRange(location: targetLocation, length: 0)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
        }

        private var baseFont: NSFont {
            NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        }
    }
}
