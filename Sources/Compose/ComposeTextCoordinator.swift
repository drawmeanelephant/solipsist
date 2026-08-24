import AppKit
import SwiftUI

/// The AppKit coordinator behind `ComposeTextView`: buffer sync, heuristic
/// painting, click-to-line / go-to-line jumps, toolbar format application
/// (#263), and the reading-comfort font ladder + gutter visibility (#264).
/// Declared in a nested-type extension so callers keep using
/// `ComposeTextView.Coordinator`.
extension ComposeTextView {
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
        /// #264: current ladder size; the single font source for this host.
        var fontSize: CGFloat = 13
        /// #264: gutter visibility, synced from `ComposeTypography`.
        var showsLineNumbers = true
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
        /// beyond 4 digits. Minimum 36pt. Collapses to the base inset when the
        /// gutter is hidden (#264).
        func updateGutterWidth() {
            guard let gutter, let textView else { return }
            guard showsLineNumbers else {
                applyGutterVisibility()
                return
            }
            let newWidth = max(gutter.gutterWidth, 36)
            if abs(gutter.frame.width - newWidth) > 0.5 {
                var gutterFrame = gutter.frame
                gutterFrame.size.width = newWidth
                gutter.frame = gutterFrame
                textView.textContainer?.lineFragmentPadding = newWidth
                textView.needsLayout = true
                gutter.needsDisplay = true
            }
        }

        /// #264: shows/hides the line-number gutter and collapses the
        /// reserved `lineFragmentPadding` back to the base inset when hidden.
        func applyGutterVisibility() {
            guard let gutter, let textView else { return }
            // Digits ride the type ladder (#264).
            gutter.fontSize = fontSize
            if gutter.isHidden != !showsLineNumbers {
                gutter.isHidden = !showsLineNumbers
                gutter.needsDisplay = true
            }
            let targetPadding: CGFloat = showsLineNumbers ? max(gutter.gutterWidth, 36) : 5
            if abs((textView.textContainer?.lineFragmentPadding ?? 0) - targetPadding) > 0.5 {
                textView.textContainer?.lineFragmentPadding = targetPadding
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

            let highlighted = ComposeHighlighter.highlight(text, language: language, fontSize: fontSize)
            if let storage = textView.textStorage {
                storage.beginEditing()
                storage.setAttributedString(highlighted)
                // #264: reading line spacing rides on the full paint.
                if highlighted.length > 0 {
                    storage.addAttribute(
                        .paragraphStyle,
                        value: paragraphStyle,
                        range: NSRange(location: 0, length: highlighted.length)
                    )
                }
                storage.endEditing()
            }
            textView.typingAttributes = [
                .font: currentFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle,
            ]
        }

        /// #264: applies a new ladder size to the buffer — font, typing
        /// attributes, and a forced full repaint so attributed sizes refresh.
        func setFontSize(_ newSize: CGFloat) {
            guard newSize != fontSize else { return }
            fontSize = newSize
            guard let textView else { return }
            textView.font = currentFont
            applyHighlight(textView, text: document.text, language: document.language, force: true)
            updateGutterWidth()
            applyGutterVisibility()
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

        /// #263: applies a toolbar format at the current selection. The
        /// mutation flows through `shouldChangeText` / `didChangeText` so the
        /// undo stack records one group per press and the ordinary
        /// `textDidChange` delegate path (buffer sync + repaint) runs
        /// unchanged.
        func apply(_ format: ComposeFormat) {
            guard let textView, document.language.supportsFormatting else { return }
            guard
                let edit = ComposeFormat.apply(
                    format,
                    to: textView.string,
                    selectedRange: textView.selectedRange(),
                    language: document.language
                )
            else { return }
            let undoManager = textView.undoManager
            undoManager?.beginUndoGrouping()
            defer { undoManager?.endUndoGrouping() }
            undoManager?.setActionName(format.actionName)
            if textView.shouldChangeText(in: edit.replacedRange, replacementString: edit.replacement) {
                textView.textStorage?.replaceCharacters(
                    in: edit.replacedRange,
                    with: edit.replacement
                )
                textView.didChangeText()
                textView.setSelectedRange(edit.selection)
            }
        }

        /// #264: the single font source for this host — the ladder size.
        var currentFont: NSFont {
            NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }

        /// #264: breathing-room paragraph style applied to typed and
        /// painted text alike.
        var paragraphStyle: NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = ComposeTypography.lineSpacing
            return style
        }
    }
}
