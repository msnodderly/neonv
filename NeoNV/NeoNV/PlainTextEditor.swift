import SwiftUI
import AppKit

// Wiki-link types
struct WikiLink: Equatable {
    let range: NSRange
    let title: String
    let isComplete: Bool  // Has closing ]]
    var matchedNote: NoteFile?
}

struct WikiLinkParser {
    static func parseWikiLinks(in text: String, notes: [NoteFile]) -> [WikiLink] {
        var links: [WikiLink] = []
        let nsText = text as NSString
        
        var searchStart = 0
        while searchStart < nsText.length {
            let openBracketRange = nsText.range(of: "[[", range: NSRange(location: searchStart, length: nsText.length - searchStart))
            guard openBracketRange.location != NSNotFound else { break }
            
            let closeBracketRange = nsText.range(of: "]]", range: NSRange(location: openBracketRange.location + 2, length: nsText.length - openBracketRange.location - 2))
            
            let endRange: NSRange
            let isComplete: Bool
            
            if closeBracketRange.location != NSNotFound {
                endRange = closeBracketRange
                isComplete = true
            } else {
                // Incomplete link - go to end of text or next [[
                let nextOpenRange = nsText.range(of: "[[", range: NSRange(location: openBracketRange.location + 2, length: nsText.length - openBracketRange.location - 2))
                if nextOpenRange.location != NSNotFound {
                    endRange = NSRange(location: nextOpenRange.location, length: 0)
                } else {
                    endRange = NSRange(location: nsText.length, length: 0)
                }
                isComplete = false
            }
            
            let linkRange = NSRange(location: openBracketRange.location, length: endRange.location - openBracketRange.location + (isComplete ? 2 : 0))
            let titleRange = NSRange(location: openBracketRange.location + 2, length: linkRange.length - 4)
            let title = titleRange.length > 0 ? nsText.substring(with: titleRange) : ""
            
            // Find matching note
            let matchedNote = notes.first { note in
                title.lowercased() == note.displayTitle.lowercased() ||
                title.lowercased() == note.title.lowercased()
            }
            
            links.append(WikiLink(
                range: linkRange,
                title: title,
                isComplete: isComplete,
                matchedNote: matchedNote
            ))
            
            searchStart = isComplete ? endRange.location + 2 : openBracketRange.location + 2
        }
        
        return links
    }
}

struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 13
    var showFindBar: Bool = false
    var searchTerms: [String] = []
    var onShiftTab: (() -> Void)?
    var onEscape: (() -> Void)?
    var availableNotes: [NoteFile] = []
    var onWikiLinkClick: ((WikiLink) -> Void)?
    var onWikiLinkCreateNote: ((String) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = CustomTextView(frame: .zero)

        textView.delegate = context.coordinator
        textView.onShiftTab = onShiftTab
        textView.onEscape = onEscape
        textView.onWikiLinkClick = onWikiLinkClick
        textView.onWikiLinkCreateNote = onWikiLinkCreateNote
        textView.availableNotes = availableNotes

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
        textView.onWikiLinkClick = onWikiLinkClick
        textView.onWikiLinkCreateNote = onWikiLinkCreateNote
        textView.availableNotes = availableNotes

        applySearchHighlighting(to: textView)
        applyDoneStrikethrough(to: textView)
        textView.updateWikiLinkStyling()

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
        Coordinator(text: $text, availableNotes: availableNotes)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var availableNotes: [NoteFile]
        
        init(text: Binding<String>, availableNotes: [NoteFile]) {
            self.text = text
            self.availableNotes = availableNotes
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
    var onWikiLinkClick: ((WikiLink) -> Void)?
    var onWikiLinkCreateNote: ((String) -> Void)?
    var availableNotes: [NoteFile] = []
    var wikiLinks: [WikiLink] = []
    
    override func mouseDown(with event: NSEvent) {
        let clickPoint = convert(event.locationInWindow, from: nil)
        let clickedRange = characterIndexForInsertion(at: clickPoint)
        
        // Check if click is on a wiki link
        for link in wikiLinks {
            if clickedRange >= link.range.location && clickedRange < link.range.location + link.range.length {
                handleWikiLinkClick(link: link, event: event)
                return
            }
        }
        
        super.mouseDown(with: event)
    }
    
    private func handleWikiLinkClick(link: WikiLink, event: NSEvent) {
        if event.modifierFlags.contains(.command) || link.matchedNote == nil {
            // Cmd+click or link to non-existent note - create or navigate
            if let matchedNote = link.matchedNote {
                onWikiLinkClick?(link)
            } else {
                onWikiLinkCreateNote?(link.title)
            }
        } else {
            // Regular click - navigate to existing note
            onWikiLinkClick?(link)
        }
    }
    
    override func keyUp(with event: NSEvent) {
        super.keyUp(with: event)
        
        // Update wiki link styling after typing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            self.updateWikiLinkStyling()
        }
    }
    
    func updateWikiLinkStyling() {
        wikiLinks = WikiLinkParser.parseWikiLinks(in: self.string, notes: availableNotes)
        
        guard let textStorage = self.textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        
        // Reset text color to default first
        textStorage.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)
        textStorage.removeAttribute(.underlineStyle, range: fullRange)
        textStorage.removeAttribute(.backgroundColor, range: fullRange)
        
        // Apply wiki-link styling
        for link in wikiLinks {
            guard link.range.location + link.range.length <= textStorage.length else { continue }
            
            if link.matchedNote != nil {
                textStorage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: link.range)
                textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: link.range)
            } else if link.isComplete {
                textStorage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: link.range)
                textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: link.range)
            } else {
                textStorage.addAttribute(.backgroundColor, value: NSColor.systemOrange.withAlphaComponent(0.2), range: link.range)
            }
        }
    }

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