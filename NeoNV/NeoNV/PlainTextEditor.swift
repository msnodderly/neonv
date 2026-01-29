import SwiftUI
import AppKit

struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 13
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

        // Enable Find Bar (Cmd-F)
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

        // Store reference for find bar activation
        context.coordinator.textView = textView

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
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: CustomTextView?
        private var findBarObserver: NSObjectProtocol?

        init(text: Binding<String>) {
            self.text = text
            super.init()

            findBarObserver = NotificationCenter.default.addObserver(
                forName: .showFindBar,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.showFindBar()
            }
        }

        deinit {
            if let observer = findBarObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        func showFindBar() {
            guard let textView = textView else { return }
            textView.window?.makeFirstResponder(textView)
            DispatchQueue.main.async {
                textView.performFindPanelAction(NSTextFinder.Action.showFindInterface)
                // The find bar is inside the enclosing scroll view; find its search field and focus it
                DispatchQueue.main.async {
                    guard let scrollView = textView.enclosingScrollView else { return }
                    if let searchField = Self.findSearchField(in: scrollView) {
                        textView.window?.makeFirstResponder(searchField)
                    }
                }
            }
        }

        /// Recursively find the NSSearchField (or NSTextField) inside the find bar view hierarchy.
        private static func findSearchField(in view: NSView) -> NSView? {
            for subview in view.subviews {
                if subview is NSSearchField {
                    return subview
                }
                if let found = findSearchField(in: subview) {
                    return found
                }
            }
            return nil
        }
    }
}

class CustomTextView: NSTextView {
    var onShiftTab: (() -> Void)?
    var onEscape: (() -> Void)?

    /// Whether the find bar is currently visible.
    var isFindBarVisible: Bool {
        guard let scrollView = enclosingScrollView else { return false }
        return scrollView.isFindBarVisible
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 && event.modifierFlags.contains(.shift) {
            onShiftTab?()
            return
        }

        if event.keyCode == 53 {
            if isFindBarVisible {
                // Dismiss the find bar with Esc
                performFindPanelAction(NSTextFinder.Action.hideFindInterface)
                return
            }
            onEscape?()
            return
        }

        super.keyDown(with: event)
    }
    
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let string = pasteboard.string(forType: .string) {
            insertText(string, replacementRange: selectedRange())
        }
    }
}

#Preview {
    PlainTextEditor(text: .constant("Hello, neonv!\n\nThis is plain text."))
        .frame(width: 400, height: 300)
}
