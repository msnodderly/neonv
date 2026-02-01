import SwiftUI
import AppKit

struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorPosition: Int
    var fontSize: CGFloat = 13
    var showFindBar: Bool = false
    var searchTerms: [String] = []
    var onShiftTab: (() -> Void)?
    var onEscape: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = FocusForwardingScrollView()
        let textView = CustomTextView(frame: .zero)

        textView.delegate = context.coordinator
        textView.onShiftTab = onShiftTab
        textView.onEscape = onEscape

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

        applySearchHighlighting(to: textView)
        applyDoneStrikethrough(to: textView)

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
    private var isControlCPending = false

    override func keyDown(with event: NSEvent) {
        // Chord: Ctrl+C, . to insert date
        if isControlCPending {
            isControlCPending = false
            if event.characters == "." {
                insertCurrentDate()
                return
            }
        }
        
        // Start of chord: Ctrl+C
        if event.modifierFlags.contains(.control) {
            if let chars = event.charactersIgnoringModifiers, chars == "c" || chars == "C" {
                isControlCPending = true
                return
            }
        }
        
        // Reset pending state if any other key is pressed (implicit above, but safe to be explicit)
        isControlCPending = false

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
}

#Preview {
    PlainTextEditor(text: .constant("Hello, neonv!\n\nThis is plain text."), cursorPosition: .constant(0))
        .frame(width: 400, height: 300)
}
