import SwiftUI
import AppKit

struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorPosition: Int
    var fontSize: CGFloat = 13
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
        textView.onShiftTab = onShiftTab
        textView.onEscape = onEscape
        textView.onWikiLinkClicked = onWikiLinkClicked
        textView.existingNoteNames = noteNamesForAutocomplete

        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
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

        // Restore cursor position (clamped to valid range)
        let safePosition = min(cursorPosition, text.count)
        textView.setSelectedRange(NSRange(location: safePosition, length: 0))

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CustomTextView else { return }

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }

        // Update font size if changed
        let expectedFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if textView.font != expectedFont {
            textView.font = expectedFont
        }

        textView.onShiftTab = onShiftTab
        textView.onEscape = onEscape
        textView.onWikiLinkClicked = onWikiLinkClicked
        textView.existingNoteNames = noteNamesForAutocomplete

        applySearchHighlighting(to: textView)
        applyDoneStrikethrough(to: textView)
        applyWikiLinkHighlighting(to: textView)

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
    
    private func applyDoneStrikethrough(to textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)

        // Remove existing strikethrough and done-line coloring
        textStorage.removeAttribute(.strikethroughStyle, range: fullRange)
        textStorage.removeAttribute(.strikethroughColor, range: fullRange)

        // Reset foreground color to default for all text
        let defaultColor = NSColor.textColor
        textStorage.addAttribute(.foregroundColor, value: defaultColor, range: fullRange)

        let text = textView.string
        let nsText = text as NSString
        let doneColor = NSColor.secondaryLabelColor

        // Find lines containing @done and apply strikethrough
        var lineStart = 0
        while lineStart < nsText.length {
            var lineEnd = 0
            var contentsEnd = 0
            nsText.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: lineStart, length: 0))

            let lineRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
            let lineContent = nsText.substring(with: lineRange)

            let isDone = lineContent.contains("@done") || lineContent.hasPrefix("- [x] ") || lineContent.hasPrefix("- [X] ")
            if isDone {
                textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: lineRange)
                textStorage.addAttribute(.strikethroughColor, value: doneColor, range: lineRange)
                textStorage.addAttribute(.foregroundColor, value: doneColor, range: lineRange)
            }

            lineStart = lineEnd
        }
    }

    /// Wiki-link regex pattern: matches [[link text]]
    static let wikiLinkPattern = try! NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]") // swiftlint:disable:this force_try

    private func applyWikiLinkHighlighting(to textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        let text = textView.string
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // Remove previous wiki-link underlines (we re-apply each cycle)
        textStorage.removeAttribute(.underlineStyle, range: fullRange)
        textStorage.removeAttribute(.cursor, range: fullRange)

        let matches = Self.wikiLinkPattern.matches(in: text, range: fullRange)
        let existingNames = existingNoteNames

        for match in matches {
            let bracketRange = match.range  // Full [[...]] range
            let linkRange = match.range(at: 1)  // Inner text range
            guard linkRange.location != NSNotFound else { continue }

            let linkName = nsText.substring(with: linkRange)
            let exists = existingNames.contains(linkName.lowercased())
            let color = exists ? NSColor.systemBlue : NSColor.systemOrange

            textStorage.addAttribute(.foregroundColor, value: color, range: bracketRange)
            textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: bracketRange)
            textStorage.addAttribute(.cursor, value: NSCursor.pointingHand, range: bracketRange)
        }
    }

    private static func focusSearchField(in view: NSView) {
        for subview in view.subviews {
            if let searchField = subview as? NSSearchField {
                searchField.window?.makeFirstResponder(searchField)
                return
            }
            focusSearchField(in: subview)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, cursorPosition: $cursorPosition)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var cursorPosition: Binding<Int>

        init(text: Binding<String>, cursorPosition: Binding<Int>) {
            self.text = text
            self.cursorPosition = cursorPosition
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            cursorPosition.wrappedValue = textView.selectedRange().location
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            cursorPosition.wrappedValue = textView.selectedRange().location
        }

        func textView(
            _ textView: NSTextView,
            rangeForUserCompletion charRange: NSRange
        ) -> NSRange {
            guard let tv = textView as? CustomTextView, tv.isWikiCompletionActive else {
                return charRange
            }

            let cursor = textView.selectedRange().location
            let ns = textView.string as NSString
            let prefix = ns.substring(to: cursor)

            guard let openRange = prefix.range(of: "[[", options: .backwards) else {
                tv.isWikiCompletionActive = false
                return charRange
            }

            let openIndex = prefix.distance(from: prefix.startIndex, to: openRange.lowerBound)
            let start = openIndex + 2

            let between = ns.substring(with: NSRange(location: start, length: cursor - start))
            if between.contains("]]") {
                tv.isWikiCompletionActive = false
                return charRange
            }

            return NSRange(location: start, length: cursor - start)
        }

        func textView(
            _ textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            guard let tv = textView as? CustomTextView, tv.isWikiCompletionActive else {
                return words
            }

            let ns = textView.string as NSString
            let query = charRange.length > 0 ? ns.substring(with: charRange) : ""
            let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            if q.contains("]") || q.contains("\n") {
                tv.isWikiCompletionActive = false
                return []
            }

            let candidates = tv.existingNoteNames

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
    }
}

fileprivate class FocusForwardingScrollView: NSScrollView {
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
    var existingNoteNames: [String] = []
    var isWikiCompletionActive = false
    var isInsertingCompletion = false

    override func mouseDown(with event: NSEvent) {
        // Check for Cmd+Click on wiki-links
        guard event.modifierFlags.contains(.command) || event.clickCount == 1 else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)
        let nsText = string as NSString

        if charIndex < nsText.length {
            let fullRange = NSRange(location: 0, length: nsText.length)
            let matches = PlainTextEditor.wikiLinkPattern.matches(in: string, range: fullRange)

            for match in matches {
                let bracketRange = match.range
                let linkRange = match.range(at: 1)
                if NSLocationInRange(charIndex, bracketRange), linkRange.location != NSNotFound {
                    let linkName = nsText.substring(with: linkRange)
                    onWikiLinkClicked?(linkName)
                    return
                }
            }
        }

        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // Cmd+Shift+D to insert date
        if event.modifierFlags.contains([.command, .shift]),
           let chars = event.charactersIgnoringModifiers, chars.lowercased() == "d" {
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
            undoManager.registerUndo(withTarget: self) { target in
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
                    DispatchQueue.main.async { [weak self] in self?.complete(nil) }
                }
            }
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
