import AppKit

/// Line numbers gutter for the compose editor (#226).
///
/// Lightweight `NSView` overlay that lives as a subview of the `NSTextView`
/// (so it scrolls vertically with the buffer but stays fixed horizontally
/// because `widthTracksTextView` disables horizontal scrolling). It draws
/// monospaced 13pt numbers in `secondaryLabelColor`, highlights the current
/// line, and shows a thin separator. Width is at least 36pt (3–4 digits for
/// ~9999 lines).
final class ComposeLineGutter: NSView {
    weak var textView: NSTextView?

    /// Fixed minimum width; grows only if line count needs more digits.
    var gutterWidth: CGFloat {
        guard let textView else { return 36 }
        let lines = max(1, lineCount(in: textView.string))
        let digits = max(3, "\(lines)".count)
        let charWidth: CGFloat = fontSize * 0.6 // ~monospace average
        let computed = CGFloat(digits) * charWidth + 12
        return max(36, computed)
    }

    /// #264: the gutter digits ride the reading-comfort type ladder.
    var fontSize: CGFloat = 13 {
        didSet {
            guard oldValue != fontSize else { return }
            needsDisplay = true
        }
    }

    private var baseFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    private var boldFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
    }

    override var isOpaque: Bool { false }

    // swiftlint:disable:next function_body_length
    override func draw(_ dirtyRect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return }

        // Background
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        // Separator at right edge
        NSColor.separatorColor.setStroke()
        let sep = NSBezierPath()
        sep.move(to: NSPoint(x: bounds.width - 0.5, y: bounds.minY))
        sep.line(to: NSPoint(x: bounds.width - 0.5, y: bounds.maxY))
        sep.lineWidth = 0.5
        sep.stroke()

        let text = textView.string as NSString
        let currentLine = currentLineNumber(in: textView)

        // Visible optimization: only draw lines whose y is in visible rect.
        // For gutter-as-subview-of-textView, visibleRect is the portion of the
        // gutter actually exposed by the clipView. Use textView's layout to
        // compute each logical line's y.
        var lineNumber = 1
        var hasDrawn = false

        // Enumerate logical lines (by \n, handling \r\n via NSString enumeration)
        text.enumerateSubstrings(
            in: NSRange(location: 0, length: text.length),
            options: [.byLines, .substringNotRequired]
        ) { _, range, _, _ in
            self.drawNumber(
                lineNumber,
                atCharacterRange: range,
                layoutManager: layoutManager,
                textView: textView,
                isCurrent: lineNumber == currentLine
            )
            hasDrawn = true
            lineNumber += 1
        }

        // Empty buffer: show line 1
        if !hasDrawn {
            drawNumber(
                1,
                atCharacterRange: NSRange(location: 0, length: 0),
                layoutManager: layoutManager,
                textView: textView,
                isCurrent: currentLine == 1
            )
            lineNumber = 2
        }

        // Trailing empty line (text ends with \n creates an extra logical line)
        if text.length > 0, text.character(at: text.length - 1) == 10 { // \n
            let range = NSRange(location: text.length, length: 0)
            drawNumber(
                lineNumber,
                atCharacterRange: range,
                layoutManager: layoutManager,
                textView: textView,
                isCurrent: lineNumber == currentLine
            )
            lineNumber += 1
        }
    }

    // MARK: - Helpers

    private func lineCount(in text: String) -> Int {
        if text.isEmpty { return 1 }
        let nsText = text as NSString
        var lines = 0
        nsText.enumerateSubstrings(
            in: NSRange(location: 0, length: nsText.length),
            options: [.byLines, .substringNotRequired]
        ) { _, _, _, _ in lines += 1 }
        if nsText.length > 0, nsText.character(at: nsText.length - 1) == 10 {
            lines += 1
        }
        return max(1, lines)
    }

    private func currentLineNumber(in textView: NSTextView) -> Int {
        let selected = textView.selectedRange().location
        let text = textView.string as NSString
        if text.length == 0 { return 1 }
        var line = 1
        var found = 1
        text.enumerateSubstrings(
            in: NSRange(location: 0, length: text.length),
            options: [.byLines, .substringNotRequired]
        ) { _, range, _, stop in
            if NSLocationInRange(selected, range) || selected == range.upperBound {
                found = line
                stop.pointee = true
            }
            // Also handle trailing empty line: selection at end == last line
            line += 1
        }
        // If selection is at very end past last line's range (trailing \n case)
        if selected == text.length, text.character(at: text.length - 1) == 10 {
            // That is the trailing empty line
            var count = 0
            text.enumerateSubstrings(
                in: NSRange(location: 0, length: text.length),
                options: [.byLines, .substringNotRequired]
            ) { _, _, _, _ in count += 1 }
            return count + 1
        }
        return found
    }

    private func drawNumber(
        _ number: Int,
        atCharacterRange range: NSRange,
        layoutManager: NSLayoutManager,
        textView: NSTextView,
        isCurrent: Bool
    ) {
        // Resolve y for this character range via layoutManager
        let glyphIndex: Int
        if range.length == 0, range.location > 0 {
            glyphIndex = layoutManager.glyphIndexForCharacter(at: max(0, range.location - 1))
        } else if range.location < (textView.string as NSString).length {
            glyphIndex = layoutManager.glyphIndexForCharacter(at: range.location)
        } else if (textView.string as NSString).length > 0 {
            glyphIndex = layoutManager.glyphIndexForCharacter(at: (textView.string as NSString).length - 1)
        } else {
            glyphIndex = 0
        }
        var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        // lineRect is in textContainer coordinates; offset by inset to get textView coords
        var yInTextView = lineRect.minY + textView.textContainerInset.height
        // For trailing empty line, place it one lineHeight below last fragment
        let isTrailingEmpty = range.location == (textView.string as NSString).length
            && range.length == 0 && (textView.string as NSString).length > 0
        if isTrailingEmpty {
            yInTextView = lineRect.maxY + textView.textContainerInset.height
            lineRect = NSRect(
                x: 0,
                y: yInTextView - textView.textContainerInset.height,
                width: 0,
                height: lineRect.height
            )
        }

        // Gutter's coordinate system is the textView's coordinate system (since gutter is subview of textView at (0,0)).
        // So yInGutter == yInTextView
        let gutterYPos = yInTextView
        let lineHeight = layoutManager.defaultLineHeight(for: baseFont)
        // Cull offscreen numbers (gutter's visibleRect is clipped by scrollView)
        let visible = visibleRect
        if gutterYPos + lineHeight < visible.minY || gutterYPos > visible.maxY + visible.height {
            // Still draw if within dirtyRect's expansion — keep cheap cull conservative
            if gutterYPos + lineHeight < bounds.minY || gutterYPos > bounds.maxY {
                return
            }
        }

        // Highlight current line background
        if isCurrent {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.12).setFill()
            let bgRect = NSRect(x: 0, y: gutterYPos, width: bounds.width, height: lineHeight)
            bgRect.fill()
        }

        let numberString = "\(number)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: isCurrent ? boldFont : baseFont,
            .foregroundColor: isCurrent ? NSColor.labelColor : NSColor.secondaryLabelColor,
        ]
        let size = numberString.size(withAttributes: attrs)
        // Right-aligned inside gutter, with 6pt right padding before separator
        let drawX = bounds.width - size.width - 6
        let drawY = gutterYPos + (lineHeight - size.height) / 2
        numberString.draw(at: NSPoint(x: drawX, y: drawY), withAttributes: attrs)
    }

    /// Click to select line (nice-to-have)
    override func mouseDown(with event: NSEvent) {
        guard let textView,
              let layoutManager = textView.layoutManager
        else { super.mouseDown(with: event)
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        // Find nearest line number by y
        let text = textView.string as NSString
        var bestRange: NSRange?
        var bestYDistance = CGFloat.greatestFiniteMagnitude
        text.enumerateSubstrings(
            in: NSRange(location: 0, length: text.length),
            options: [.byLines, .substringNotRequired]
        ) { _, range, _, _ in
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: range.location)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let gutterY = lineRect.minY + textView.textContainerInset.height
            let distance = abs(location.y - (gutterY + lineRect.height / 2))
            if distance < bestYDistance {
                bestYDistance = distance
                bestRange = range
            }
        }
        if let bestRange {
            // Select the line's character range (without trailing \n)
            let lineRange = (text as NSString).lineRange(for: bestRange)
            // Trim trailing newline for selection, but include content
            let selectLength = NSMaxRange(lineRange) > text.length ? text.length - lineRange.location : lineRange.length
            // If line ends with \n, exclude it from selection to mimic Xcode
            var length = selectLength
            if length > 0, text.character(at: lineRange.location + length - 1) == 10 {
                length -= 1
            }
            let selectRange = NSRange(location: lineRange.location, length: length)
            textView.setSelectedRange(selectRange)
            textView.window?.makeFirstResponder(textView)
        } else {
            super.mouseDown(with: event)
        }
    }
}
