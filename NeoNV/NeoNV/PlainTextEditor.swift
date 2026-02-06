import SwiftUI
import AppKit

struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorPosition: Int
    var fontSize: CGFloat = 13
    var fontFamily: String = ""
    var showFindBar: Bool = false
    var searchTerms: [String] = []
    var existingNoteNames: Set<String> = []
    var noteNamesForAutocomplete: [String] = []
    var onShiftTab: (() -> Void)?
    var onEscape: (() -> Void)?
    var onWikiLinkClicked: ((String) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = FocusForwardingScrollView()
        let textView = CustomTextView(frame: .zero)

        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        context.coordinator.textView = textView
        textView.onShiftTab = onShiftTab
        textView.onEscape = onEscape
        textView.onWikiLinkClicked = onWikiLinkClicked
        textView.autocompleteNoteNames = noteNamesForAutocomplete
        context.coordinator.existingNoteNames = existingNoteNames
        context.coordinator.lastWikiLinkNames = existingNoteNames

        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = resolvedFont()
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isEditable = true
        textView.isSelectable = true
        textView.autoresizingMask = [.width, .height]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.layoutManager?.allowsNonContiguousLayout = true

        // Disable automatic substitutions for a true plain text experience
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        textView.string = text

        // Apply initial done-styling for the full document
        context.coordinator.applyDoneAttributesFullDocument()

        // Restore cursor position (clamped to valid range)
        let safePosition = min(cursorPosition, text.count)
        textView.setSelectedRange(NSRange(location: safePosition, length: 0))

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CustomTextView else { return }

        // Use normalized comparison to avoid unnecessary updates from line-ending differences
        // that cause scroll jumps and cursor instability.
        let normalizedText = text.replacingOccurrences(of: "\r\n", with: "\n")
        let textChanged = textView.string != normalizedText
        
        if textChanged {
            let selectedRanges = textView.selectedRanges
            textView.string = normalizedText
            textView.selectedRanges = selectedRanges
        }

        // Sync cursor position only when NOT actively editing (avoids feedback loop)
        let isEditing = (textView.window?.firstResponder === textView)
        let currentRange = textView.selectedRange()
        if !isEditing, currentRange.length == 0, currentRange.location != cursorPosition {
            let safePosition = min(cursorPosition, textView.string.count)
            textView.setSelectedRange(NSRange(location: safePosition, length: 0))
        }

        // Update font only if actually different (compare by name/size to avoid layout churn)
        let expectedFont = resolvedFont()
        if textView.font?.fontName != expectedFont.fontName ||
           textView.font?.pointSize != expectedFont.pointSize {
            textView.font = expectedFont
        }

        textView.onShiftTab = onShiftTab
        textView.onEscape = onEscape
        textView.onWikiLinkClicked = onWikiLinkClicked
        textView.autocompleteNoteNames = noteNamesForAutocomplete
        context.coordinator.existingNoteNames = existingNoteNames

        // Only re-apply highlighting if text or search terms changed
        if textChanged || context.coordinator.lastSearchTerms != searchTerms {
            applySearchHighlighting(to: textView)
            context.coordinator.lastSearchTerms = searchTerms
        }
        
        let wikiNamesChanged = context.coordinator.lastWikiLinkNames != existingNoteNames

        // Apply full done-styling only when switching to a new document or when wiki names change.
        if textChanged || wikiNamesChanged {
            context.coordinator.applyDoneAttributesFullDocument()
        }

        if wikiNamesChanged {
            context.coordinator.lastWikiLinkNames = existingNoteNames
        }

        if showFindBar {
            if !scrollView.isFindBarVisible {
                let menuItem = NSMenuItem()
                menuItem.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
                textView.performTextFinderAction(menuItem)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let findBarContainer = scrollView.findBarView {
                    PlainTextEditor.focusSearchField(in: findBarContainer)
                }
            }
        }
    }

    private func applySearchHighlighting(to textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        
        textStorage.beginEditing()
        defer { textStorage.endEditing() }
        
        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.removeAttribute(.backgroundColor, range: fullRange)

        guard !searchTerms.isEmpty else { return }

        let text = textView.string
        let nsText = text as NSString
        let highlightColor = NSColor.systemYellow.withAlphaComponent(0.4)

        for term in searchTerms where !term.isEmpty {
            var searchRange = NSRange(location: 0, length: nsText.length)
            while searchRange.location < nsText.length {
                let foundRange = nsText.range(
                    of: term,
                    options: .caseInsensitive,
                    range: searchRange
                )
                if foundRange.location == NSNotFound {
                    break
                }
                textStorage.addAttribute(.backgroundColor, value: highlightColor, range: foundRange)
                searchRange.location = foundRange.location + foundRange.length
                searchRange.length = nsText.length - searchRange.location
            }
        }
    }

    /// Wiki-link regex pattern: matches [[link text]]
    fileprivate static let wikiLinkPattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]")
        } catch {
            fatalError("Invalid wiki link regex: \\(error)")
        }
    }()
    fileprivate static let wikiLinkAttribute = NSAttributedString.Key("neonvWikiLink")

    private static func focusSearchField(in view: NSView) {
        for subview in view.subviews {
            if let searchField = subview as? NSSearchField {
                searchField.window?.makeFirstResponder(searchField)
                return
            }
            focusSearchField(in: subview)
        }
    }

    private func resolvedFont() -> NSFont {
        if !fontFamily.isEmpty, let font = NSFont(name: fontFamily, size: fontSize) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, cursorPosition: $cursorPosition)
    }

    class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var text: Binding<String>
        var cursorPosition: Binding<Int>
        var lastSearchTerms: [String] = []
        var lastWikiLinkNames: Set<String> = []
        var existingNoteNames: Set<String> = []
        weak var textView: NSTextView?
        private var isApplyingDoneAttributes = false
        private var pendingDoneRange: NSRange?
        private var scheduledDoneApply = false

        init(text: Binding<String>, cursorPosition: Binding<Int>) {
            self.text = text
            self.cursorPosition = cursorPosition
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newText = textView.string
            if text.wrappedValue != newText {
                text.wrappedValue = newText
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let loc = textView.selectedRange().location
            if cursorPosition.wrappedValue != loc {
                cursorPosition.wrappedValue = loc
            }
        }

        func textView(
            _ textView: NSTextView,
            rangeForUserCompletion charRange: NSRange
        ) -> NSRange {
            guard let tv = textView as? CustomTextView else { return charRange }

            guard let range = wikiCompletionRange(in: textView) else {
                tv.isWikiCompletionActive = false
                return charRange
            }

            tv.isWikiCompletionActive = true
            return range
        }

        func textView(
            _ textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            guard let tv = textView as? CustomTextView else { return words }

            guard let range = wikiCompletionRange(in: textView) else {
                tv.isWikiCompletionActive = false
                return words
            }

            tv.isWikiCompletionActive = true

            let ns = textView.string as NSString
            let query = range.length > 0 ? ns.substring(with: range) : ""
            let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            if q.contains("]") || q.contains("\n") {
                tv.isWikiCompletionActive = false
                return []
            }

            let candidates = tv.autocompleteNoteNames

            func isSubsequence(_ needle: String, _ haystack: String) -> Bool {
                var it = haystack.makeIterator()
                for c in needle {
                    var found = false
                    while let h = it.next() {
                        if h == c {
                            found = true
                            break
                        }
                    }
                    if !found { return false }
                }
                return true
            }

            func score(_ title: String) -> Int? {
                if q.isEmpty { return 0 }
                let t = title.lowercased()
                if t.hasPrefix(q) { return 0 }
                if t.contains(q) { return 1 }
                if isSubsequence(q, t) { return 2 }
                return nil
            }

            let ranked = candidates.compactMap { title -> (String, Int)? in
                guard let s = score(title) else { return nil }
                return (title, s)
            }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 < b.1 }
                return a.0.count < b.0.count
            }
            .map(\.0)

            index?.pointee = 0
            return Array(ranked.prefix(50))
        }

        private func wikiCompletionRange(in textView: NSTextView) -> NSRange? {
            let cursor = textView.selectedRange().location
            let ns = textView.string as NSString
            guard cursor <= ns.length else { return nil }
            let prefix = ns.substring(to: cursor)

            guard let openRange = prefix.range(of: "[[", options: .backwards) else {
                return nil
            }

            let openIndex = prefix.distance(from: prefix.startIndex, to: openRange.lowerBound)
            let start = openIndex + 2

            let between = ns.substring(with: NSRange(location: start, length: cursor - start))
            if between.contains("]]") {
                return nil
            }

            return NSRange(location: start, length: cursor - start)
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard !isApplyingDoneAttributes,
                  editedMask.contains(.editedCharacters)
            else { return }

            let ns = textStorage.string as NSString
            guard ns.length > 0, editedRange.location < ns.length else { return }

            // Expand to full line(s) containing the edit
            let affected = ns.lineRange(for: editedRange)

            // Merge ranges to coalesce multiple rapid edits
            if let existing = pendingDoneRange {
                let start = min(existing.location, affected.location)
                let end = max(NSMaxRange(existing), NSMaxRange(affected))
                pendingDoneRange = NSRange(location: start, length: end - start)
            } else {
                pendingDoneRange = affected
            }

            // Schedule coalesced apply on next runloop to avoid layout thrash
            guard !scheduledDoneApply else { return }
            scheduledDoneApply = true

            DispatchQueue.main.async { [weak self, weak textStorage] in
                guard let self, let textStorage, let range = self.pendingDoneRange else { return }
                self.pendingDoneRange = nil
                self.scheduledDoneApply = false
                self.applyDoneAttributes(textStorage: textStorage, in: range)
            }
        }

        private func applyDoneAttributes(textStorage: NSTextStorage, in range: NSRange) {
            isApplyingDoneAttributes = true
            defer { isApplyingDoneAttributes = false }

            let ns = textStorage.string as NSString
            let doneColor = NSColor.secondaryLabelColor

            textStorage.beginEditing()
            defer { textStorage.endEditing() }

            clearWikiAttributes(textStorage: textStorage, in: range)

            var lineStart = range.location
            let end = NSMaxRange(range)

            while lineStart < end, lineStart < ns.length {
                var lineEnd = 0
                var contentsEnd = 0
                ns.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd,
                                for: NSRange(location: lineStart, length: 0))

                let lineRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
                let lineContent = ns.substring(with: lineRange)

                let isDone = lineContent.contains("@done")
                          || lineContent.hasPrefix("- [x] ")
                          || lineContent.hasPrefix("- [X] ")

                if isDone {
                    textStorage.addAttribute(.strikethroughStyle,
                                             value: NSUnderlineStyle.single.rawValue,
                                             range: lineRange)
                    textStorage.addAttribute(.strikethroughColor, value: doneColor, range: lineRange)
                    textStorage.addAttribute(.foregroundColor, value: doneColor, range: lineRange)
                } else {
                    textStorage.removeAttribute(.strikethroughStyle, range: lineRange)
                    textStorage.removeAttribute(.strikethroughColor, range: lineRange)
                    // Set explicit text color to respect dark/light mode (removing the attribute
                    // causes fallback to black, which is unreadable in dark mode)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.textColor, range: lineRange)
                }

                lineStart = lineEnd
            }

            applyWikiAttributes(textStorage: textStorage, in: range)
        }

        func applyDoneAttributesFullDocument() {
            guard let textView = textView,
                  let textStorage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: textStorage.length)
            applyDoneAttributes(textStorage: textStorage, in: fullRange)
        }

        private func clearWikiAttributes(textStorage: NSTextStorage, in range: NSRange) {
            textStorage.enumerateAttribute(
                PlainTextEditor.wikiLinkAttribute,
                in: range,
                options: []
            ) { value, attrRange, _ in
                guard value != nil else { return }
                textStorage.removeAttribute(.underlineStyle, range: attrRange)
                textStorage.removeAttribute(.underlineColor, range: attrRange)
                textStorage.removeAttribute(.cursor, range: attrRange)
                textStorage.removeAttribute(.foregroundColor, range: attrRange)
                textStorage.removeAttribute(PlainTextEditor.wikiLinkAttribute, range: attrRange)
            }
        }

        private func applyWikiAttributes(textStorage: NSTextStorage, in range: NSRange) {
            let text = textStorage.string
            let nsText = text as NSString
            let matches = PlainTextEditor.wikiLinkPattern.matches(in: text, range: range)

            for match in matches {
                let bracketRange = match.range
                let linkRange = match.range(at: 1)
                guard linkRange.location != NSNotFound else { continue }

                let linkName = nsText.substring(with: linkRange)
                let exists = existingNoteNames.contains(linkName.lowercased())
                let color = exists ? NSColor.systemBlue : NSColor.systemOrange

                textStorage.addAttribute(.foregroundColor, value: color, range: bracketRange)
                textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: bracketRange)
                textStorage.addAttribute(.underlineColor, value: color, range: bracketRange)
                textStorage.addAttribute(.cursor, value: NSCursor.pointingHand, range: bracketRange)
                textStorage.addAttribute(PlainTextEditor.wikiLinkAttribute, value: linkName, range: bracketRange)
            }
        }
    }
}

private class FocusForwardingScrollView: NSScrollView {
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        if let docView = documentView {
            return window?.makeFirstResponder(docView) ?? false
        }
        return super.becomeFirstResponder()
    }
}

class CustomTextView: NSTextView {
    var onShiftTab: (() -> Void)?
    var onEscape: (() -> Void)?
    var onWikiLinkClicked: ((String) -> Void)?
    var autocompleteNoteNames: [String] = []
    var isWikiCompletionActive = false
    var isInsertingCompletion = false

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 1 else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)
        if let textStorage = textStorage, charIndex < textStorage.length {
            var effectiveRange = NSRange(location: 0, length: 0)
            if let linkName = textStorage.attribute(
                PlainTextEditor.wikiLinkAttribute,
                at: charIndex,
                effectiveRange: &effectiveRange
            ) as? String {
                onWikiLinkClicked?(linkName)
                return
            }
        }

        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // Cmd+Shift+D or Cmd+Period to insert date
        if event.modifierFlags.contains([.command, .shift]),
           let chars = event.charactersIgnoringModifiers, chars.lowercased() == "d" {
            insertCurrentDate()
            return
        }
        
        // Cmd+Period (keyCode 47) as alternate shortcut for insert date
        if event.keyCode == 47 && event.modifierFlags.contains(.command) &&
           !event.modifierFlags.contains(.shift) && !event.modifierFlags.contains(.option) {
            insertCurrentDate()
            return
        }

        if event.keyCode == 48 && event.modifierFlags.contains(.shift) {
            onShiftTab?()
            return
        }

        if event.keyCode == 53 {
            // Let completion panel handle Escape when active
            if isWikiCompletionActive {
                super.keyDown(with: event)
                return
            }
            // If the find bar is visible, dismiss it
            if let scrollView = enclosingScrollView, scrollView.isFindBarVisible {
                let menuItem = NSMenuItem()
                menuItem.tag = Int(NSTextFinder.Action.hideFindInterface.rawValue)
                performTextFinderAction(menuItem)
                return
            }
            onEscape?()
            return
        }
        
        super.keyDown(with: event)
    }

    private func insertCurrentDate() {
        let formatter = DateFormatter()
        // Org-mode inactive timestamp format: [YYYY-MM-DD Day HH:MM]
        formatter.dateFormat = "[yyyy-MM-dd EEE HH:mm]"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let dateString = formatter.string(from: Date())
        
        if let undoManager = undoManager {
            undoManager.registerUndo(withTarget: self) { _ in
                // Simple undo implementation: delete the inserted text
                // In a real app, we rely on the text view's native undo grouping,
                // but explicit registration helps ensure the action is atomic.
                // However, insertText handles undo automatically.
            }
        }
        
        insertText(dateString, replacementRange: selectedRange())
    }

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let string = pasteboard.string(forType: .string) {
            insertText(string, replacementRange: selectedRange())
        }
    }

    override func pasteAsRichText(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        guard !isInsertingCompletion else { return }

        guard let str = insertString as? String else { return }
        if str == "[" {
            let loc = selectedRange().location
            if loc >= 2 {
                let ns = string as NSString
                if ns.substring(with: NSRange(location: loc - 2, length: 2)) == "[[" {
                    isWikiCompletionActive = true
                }
            }
        }

        if isWikiCompletionActive {
            DispatchQueue.main.async { [weak self] in self?.complete(nil) }
        }
    }

    override func insertCompletion(
        _ word: String,
        forPartialWordRange charRange: NSRange,
        movement: Int,
        isFinal: Bool
    ) {
        isInsertingCompletion = true
        super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: isFinal)
        isInsertingCompletion = false

        guard isFinal else { return }

        if movement == NSCancelTextMovement {
            isWikiCompletionActive = false
            return
        }

        if movement == NSReturnTextMovement || movement == NSTabTextMovement {
            let cursor = selectedRange().location
            let ns = string as NSString
            let suffix = cursor + 2 <= ns.length
                ? ns.substring(with: NSRange(location: cursor, length: 2))
                : ""

            if suffix != "]]" {
                isInsertingCompletion = true
                insertText("]]", replacementRange: NSRange(location: cursor, length: 0))
                isInsertingCompletion = false
            }
            setSelectedRange(NSRange(location: selectedRange().location, length: 0))
            isWikiCompletionActive = false
        }
    }
}

#Preview {
    PlainTextEditor(text: .constant("Hello, neonv!\n\nThis is plain text."), cursorPosition: .constant(0))
        .frame(width: 400, height: 300)
}
