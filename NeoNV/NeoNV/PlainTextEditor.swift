import SwiftUI
import AppKit

struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 13
    var showFindBar: Bool = false
    var onShiftTab: (() -> Void)?
    var onEscape: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = CustomTextView()

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

        if showFindBar {
            if !scrollView.isFindBarVisible {
                // Show the find bar
                let menuItem = NSMenuItem()
                menuItem.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
                textView.performTextFinderAction(menuItem)
            }
            // Focus the find bar's search field (whether just opened or already visible)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let findBarContainer = scrollView.findBarView {
                    PlainTextEditor.focusSearchField(in: findBarContainer)
                }
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

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        
        init(text: Binding<String>) {
            self.text = text
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

class CustomTextView: NSTextView {
    var onShiftTab: (() -> Void)?
    var onEscape: (() -> Void)?
    
    override func keyDown(with event: NSEvent) {
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
    PlainTextEditor(text: .constant("Hello, neonv!\n\nThis is plain text."))
        .frame(width: 400, height: 300)
}
