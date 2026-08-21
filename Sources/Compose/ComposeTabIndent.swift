import AppKit

private enum ComposeTabIndentDirection {
    case indent
    case outdent
}

@MainActor
extension ComposeTextView.Coordinator {
    // MARK: - Tab indent (#229)

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            if shouldAllowTabIndent(in: textView) {
                indent(textView, direction: .indent)
                return true
            }
            return false
        }
        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            if shouldAllowTabOutdent(in: textView) {
                indent(textView, direction: .outdent)
                return true
            }
            return false
        }
        return false
    }

    private func shouldAllowTabIndent(in textView: NSTextView) -> Bool {
        if let scrollView, isFindBarVisible(in: scrollView) { return false }
        if isCookCompletionActive(in: textView) { return false }
        return true
    }

    private func isCookCompletionActive(in textView: NSTextView) -> Bool {
        guard document.language == .cooklang, !completion.isEmpty else { return false }
        let range = textView.rangeForUserCompletion
        guard range.location != NSNotFound else { return false }
        let nsText = textView.string as NSString
        // Completion is anchored to a partial word; use the range AppKit
        // provides, but only treat it as active when a Cooklang marker
        // precedes it and there are actual suggestions.
        let prefix: String
        if range.location == NSNotFound || range.length == 0 {
            // No partial word range; check one-character behind the caret
            // is a marker (covers the bare "@" insertion case).
            let caret = textView.selectedRange().location
            guard caret > 0 else { return false }
            guard let marker = CookMarkerScanner.marker(before: caret, in: nsText) else { return false }
            prefix = ""
            return !completion.suggestions(marker: marker, prefix: prefix).isEmpty
        }
        guard range.location > 0 else { return false }
        guard let marker = CookMarkerScanner.marker(before: range.location, in: nsText) else { return false }
        if range.location + range.length <= nsText.length {
            prefix = nsText.substring(with: range)
        } else {
            prefix = ""
        }
        return !completion.suggestions(marker: marker, prefix: prefix).isEmpty
    }

    private func shouldAllowTabOutdent(in textView: NSTextView) -> Bool {
        if let scrollView, isFindBarVisible(in: scrollView) { return false }
        return true
    }

    private func isFindBarVisible(in scrollView: NSScrollView) -> Bool {
        if scrollView.responds(to: Selector(("isFindBarVisible"))) {
            if let value = scrollView.value(forKey: "findBarVisible") as? Bool { return value }
            // Fallback via performSelector for the isFindBarVisible variant.
            if let number = scrollView.perform(Selector(("isFindBarVisible")))?.takeUnretainedValue() as? NSNumber {
                return number.boolValue
            }
        }
        if scrollView.responds(to: Selector(("findBarVisible"))) {
            if let value = scrollView.value(forKey: "findBarVisible") as? Bool { return value }
            if let number = scrollView.perform(Selector(("findBarVisible")))?.takeUnretainedValue() as? NSNumber {
                return number.boolValue
            }
        }
        return false
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func indent(_ textView: NSTextView, direction: ComposeTabIndentDirection) {
        guard let storage = textView.textStorage else { return }
        let nsText = textView.string as NSString
        let selectedRange = textView.selectedRange()
        let lineStarts = collectLineStarts(for: selectedRange, in: nsText)
        guard !lineStarts.isEmpty else { return }

        var removedMap: [Int: Int] = [:]
        if direction == .outdent {
            for start in lineStarts {
                let remaining = nsText.length - start
                guard remaining > 0 else { continue }
                let prefix = nsText.substring(with: NSRange(location: start, length: min(2, remaining)))
                if prefix.hasPrefix("  ") {
                    removedMap[start] = 2
                } else if prefix.hasPrefix(" ") || prefix.hasPrefix("\t") {
                    removedMap[start] = 1
                }
            }
        }

        // Wrap the multi-line edit in a single undo group so ⌘Z reverts
        // all affected lines atomically (indenting 10 lines = one step).
        textView.undoManager?.beginUndoGrouping()
        storage.beginEditing()
        for start in lineStarts.reversed() {
            if direction == .indent {
                let range = NSRange(location: start, length: 0)
                if textView.shouldChangeText(in: range, replacementString: "  ") {
                    storage.replaceCharacters(in: range, with: "  ")
                    textView.didChangeText()
                }
            } else if let removeLength = removedMap[start], removeLength > 0 {
                let range = NSRange(location: start, length: removeLength)
                if textView.shouldChangeText(in: range, replacementString: "") {
                    storage.replaceCharacters(in: range, with: "")
                    textView.didChangeText()
                }
            }
        }
        storage.endEditing()
        textView.undoManager?.endUndoGrouping()

        // Keep the buffer's source-of-truth in sync eagerly; textDidChange
        // will also fire, but this guarantees document.text is current for
        // cursor/highlight observers even when the notification coalesces.
        document.text = textView.string

        let newRange = shiftedRange(for: selectedRange, lineStarts: lineStarts, direction: direction, removedMap: removedMap)
        let clamped = clampedRange(newRange, in: textView)
        textView.setSelectedRange(clamped)
        document.updateCursor(clamped)
        updateGutterWidth()
        gutter?.needsDisplay = true
    }

    private func collectLineStarts(for range: NSRange, in nsText: NSString) -> [Int] {
        let lineRange: NSRange
        if range.length == 0 {
            lineRange = nsText.lineRange(for: NSRange(location: range.location, length: 0))
        } else {
            lineRange = nsText.lineRange(for: range)
        }
        var starts: [Int] = []
        var searchLocation = lineRange.location
        let end = NSMaxRange(lineRange)
        while searchLocation < end, searchLocation < nsText.length {
            let line = nsText.lineRange(for: NSRange(location: searchLocation, length: 0))
            starts.append(line.location)
            let next = NSMaxRange(line)
            if next <= searchLocation { break }
            searchLocation = next
            if searchLocation >= end { break }
        }
        if starts.isEmpty { starts.append(lineRange.location) }
        return starts
    }

    private func shiftedRange(
        for range: NSRange,
        lineStarts: [Int],
        direction: ComposeTabIndentDirection,
        removedMap: [Int: Int]
    ) -> NSRange {
        let newLocation = shiftedOffset(range.location, lineStarts: lineStarts, direction: direction, removedMap: removedMap)
        let newEnd = shiftedOffset(NSMaxRange(range), lineStarts: lineStarts, direction: direction, removedMap: removedMap)
        return NSRange(location: newLocation, length: newEnd - newLocation)
    }

    private func shiftedOffset(
        _ offset: Int,
        lineStarts: [Int],
        direction: ComposeTabIndentDirection,
        removedMap: [Int: Int]
    ) -> Int {
        var shift = 0
        for start in lineStarts {
            if direction == .indent {
                if start <= offset { shift += 2 }
            } else {
                let removed = removedMap[start] ?? 0
                if removed == 0 { continue }
                if offset >= start + removed {
                    shift -= removed
                } else if offset > start {
                    shift -= (offset - start)
                }
            }
        }
        return offset + shift
    }

    private func clampedRange(_ range: NSRange, in textView: NSTextView) -> NSRange {
        let length = (textView.string as NSString).length
        let loc = min(max(range.location, 0), length)
        let len = min(max(range.length, 0), length - loc)
        return NSRange(location: loc, length: len)
    }
}
