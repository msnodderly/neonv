import SwiftUI
import AppKit

struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorPosition: Int
    var fontSize: CGFloat = 13
    var fontFamily: String = ""
    var showFindBar: Bool = false
    var searchTerms: [String] = []
    var onShiftTab: (() -> Void)?
    var onEscape: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = FocusForwardingScrollView()
        let textView = CustomTextView(frame: .zero)

        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        context.coordinator.textView = textView
        textView.onShiftTab = onShiftTab
        textView.onEscape = onEscape

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

        // Only re-apply highlighting if text or search terms changed
        if textChanged || context.coordinator.lastSearchTerms != searchTerms {
            applySearchHighlighting(to: textView)
            context.coordinator.lastSearchTerms = searchTerms
        }
        
        // Apply full done-styling only when switching to a new document
        if textChanged {
            context.coordinator.applyDoneAttributesFullDocument()
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
        }

        func applyDoneAttributesFullDocument() {
            guard let textView = textView,
                  let textStorage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: textStorage.length)
            applyDoneAttributes(textStorage: textStorage, in: fullRange)
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
}

#Preview {
    PlainTextEditor(text: .constant("Hello, neonv!\n\nThis is plain text."), cursorPosition: .constant(0))
        .frame(width: 400, height: 300)
}
