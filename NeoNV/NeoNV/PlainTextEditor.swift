import SwiftUI
import AppKit

struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorPosition: Int
    @Binding var scrollFraction: CGFloat
    var restoreScrollFraction: CGFloat?
    var fontSize: CGFloat = 13
    var fontFamily: String = ""
    var isEditable: Bool = true
    var isHiddenFromFocus: Bool = false
    var showFindBar: Bool = false
    var searchTerms: [String] = []
    var resolveWikiLink: (String) -> WikiLinkResolution = { _ in .missing("") }
    var wikiSuggestions: (String) -> [WikiLinkSuggestion] = { _ in [] }
    var wikiIndexVersion: Int = 0
    var wikiAutocompleteEnabled: Bool = true
    var onOpenWikiLink: (String) -> Void = { _ in }
    var onShiftTab: (() -> Void)?
    var onEscape: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = FocusForwardingScrollView()
        let textView = CustomTextView(frame: .zero)

        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.resolveWikiLink = resolveWikiLink
        context.coordinator.wikiSuggestions = wikiSuggestions
        context.coordinator.wikiIndexVersion = wikiIndexVersion
        context.coordinator.wikiAutocompleteEnabled = wikiAutocompleteEnabled
        textView.onShiftTab = onShiftTab
        textView.onEscape = onEscape
        textView.onTabCompletion = {
            context.coordinator.handleTabCompletion()
        }
        textView.onOpenCompletionList = {
            context.coordinator.handleOpenCompletionList()
        }
        textView.onEscapeCompletion = {
            context.coordinator.handleEscapeInCompletion()
        }
        textView.onOpenWikiLink = onOpenWikiLink

        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = resolvedFont()
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isEditable = isEditable
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
        // Keep links clickable but preserve per-link foreground colors (resolved vs missing).
        textView.linkTextAttributes = [
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        textView.refusesFocus = isHiddenFromFocus
        scrollView.refusesFocus = isHiddenFromFocus

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        textView.string = text

        // Apply initial done-styling for the full document
        context.coordinator.applyDoneAttributesFullDocument()
        applyEditorAttributes(to: textView)

        // Restore cursor position (clamped to valid range)
        let safePosition = min(cursorPosition, text.count)
        textView.setSelectedRange(NSRange(location: safePosition, length: 0))

        // Observe scroll position changes to keep scrollFraction up to date
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

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

        textView.isEditable = isEditable
        textView.onShiftTab = onShiftTab
        textView.onEscape = onEscape
        textView.onTabCompletion = {
            context.coordinator.handleTabCompletion()
        }
        textView.onOpenCompletionList = {
            context.coordinator.handleOpenCompletionList()
        }
        textView.onEscapeCompletion = {
            context.coordinator.handleEscapeInCompletion()
        }
        textView.onOpenWikiLink = onOpenWikiLink
        context.coordinator.resolveWikiLink = resolveWikiLink
        context.coordinator.wikiSuggestions = wikiSuggestions
        context.coordinator.wikiIndexVersion = wikiIndexVersion
        context.coordinator.wikiAutocompleteEnabled = wikiAutocompleteEnabled

        textView.refusesFocus = isHiddenFromFocus
        if let focusScroll = scrollView as? FocusForwardingScrollView {
            focusScroll.refusesFocus = isHiddenFromFocus
        }
        if isHiddenFromFocus, textView.window?.firstResponder === textView {
            textView.window?.makeFirstResponder(nil)
        }

        // Apply full done-styling only when switching to a new document
        if textChanged {
            context.coordinator.applyDoneAttributesFullDocument()
        }

        // Re-apply transient editor attributes when text/search/lookup state changes.
        if textChanged ||
            context.coordinator.lastSearchTerms != searchTerms ||
            context.coordinator.lastWikiIndexVersion != wikiIndexVersion {
            applyEditorAttributes(to: textView)
            context.coordinator.lastSearchTerms = searchTerms
            context.coordinator.lastWikiIndexVersion = wikiIndexVersion
        }

        // Restore scroll position when returning from preview
        if let fraction = restoreScrollFraction, fraction >= 0 {
            let documentHeight = textView.frame.height
            let visibleHeight = scrollView.contentView.bounds.height
            let maxScroll = documentHeight - visibleHeight
            if maxScroll > 0 {
                let targetY = fraction * maxScroll
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
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

    private func applyEditorAttributes(to textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        
        textStorage.beginEditing()
        defer { textStorage.endEditing() }
        
        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.removeAttribute(.backgroundColor, range: fullRange)
        textStorage.removeAttribute(.link, range: fullRange)
        textStorage.removeAttribute(.underlineStyle, range: fullRange)

        let text = textView.string
        let nsText = text as NSString

        if text.contains("[[") {
            // Highlight wiki-links and attach internal link attributes.
            for match in WikiLinkParser.matches(in: text) {
                let resolution = resolveWikiLink(match.target)
                let linkColor: NSColor
                switch resolution {
                case .resolved:
                    linkColor = .linkColor
                case .missing, .ambiguous:
                    linkColor = .systemOrange
                }

                textStorage.addAttribute(.foregroundColor, value: linkColor, range: match.fullRange)
                textStorage.addAttribute(
                    .underlineStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: match.fullRange
                )
                if let linkURL = WikiLinkURLCodec.url(forTarget: match.target) {
                    textStorage.addAttribute(.link, value: linkURL, range: match.fullRange)
                }
            }
        }

        guard !searchTerms.isEmpty else { return }

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
        Coordinator(
            text: $text,
            cursorPosition: $cursorPosition,
            scrollFraction: $scrollFraction,
            resolveWikiLink: resolveWikiLink,
            wikiSuggestions: wikiSuggestions,
            wikiIndexVersion: wikiIndexVersion,
            wikiAutocompleteEnabled: wikiAutocompleteEnabled
        )
    }

    class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var text: Binding<String>
        var cursorPosition: Binding<Int>
        var scrollFraction: Binding<CGFloat>
        var resolveWikiLink: (String) -> WikiLinkResolution
        var wikiSuggestions: (String) -> [WikiLinkSuggestion]
        var wikiIndexVersion: Int
        var wikiAutocompleteEnabled: Bool
        var lastSearchTerms: [String] = []
        var lastWikiIndexVersion: Int = -1
        weak var textView: NSTextView?
        private var isApplyingDoneAttributes = false
        private var pendingDoneRange: NSRange?
        private var scheduledDoneApply = false
        private var pendingCompletionContext: WikiLinkContext?
        private var isApplyingCompletion = false
        private var completionSessionActive = false

        init(
            text: Binding<String>,
            cursorPosition: Binding<Int>,
            scrollFraction: Binding<CGFloat>,
            resolveWikiLink: @escaping (String) -> WikiLinkResolution,
            wikiSuggestions: @escaping (String) -> [WikiLinkSuggestion],
            wikiIndexVersion: Int,
            wikiAutocompleteEnabled: Bool
        ) {
            self.text = text
            self.cursorPosition = cursorPosition
            self.scrollFraction = scrollFraction
            self.resolveWikiLink = resolveWikiLink
            self.wikiSuggestions = wikiSuggestions
            self.wikiIndexVersion = wikiIndexVersion
            self.wikiAutocompleteEnabled = wikiAutocompleteEnabled
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newText = textView.string
            if text.wrappedValue != newText {
                text.wrappedValue = newText
            }

            // Any direct text edit should end the previous completion session state.
            completionSessionActive = false
            updateCompletionContext(for: textView)
        }

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView,
                  let scrollView = clipView.superview as? NSScrollView,
                  let documentView = scrollView.documentView else { return }
            let documentHeight = documentView.frame.height
            let visibleHeight = clipView.bounds.height
            let maxScroll = documentHeight - visibleHeight
            if maxScroll > 0 {
                scrollFraction.wrappedValue = clipView.bounds.origin.y / maxScroll
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let loc = textView.selectedRange().location
            if cursorPosition.wrappedValue != loc {
                cursorPosition.wrappedValue = loc
            }
            updateCompletionContext(for: textView)
        }

        private func updateCompletionContext(for textView: NSTextView) {
            let cursor = textView.selectedRange().location
            let nsText = textView.string as NSString
            pendingCompletionContext = WikiLinkParser.contextAtCursor(in: nsText, cursorLocation: cursor)
            if pendingCompletionContext == nil {
                completionSessionActive = false
            }
        }

        func handleEscapeInCompletion() -> Bool {
            guard completionSessionActive, let textView else { return false }
            textView.cancelOperation(nil)
            completionSessionActive = false
            return true
        }

        func handleOpenCompletionList() -> Bool {
            guard wikiAutocompleteEnabled,
                  let textView,
                  let context = pendingCompletionContext
            else { return false }

            // If completion UI is already active, let AppKit handle arrow navigation.
            guard !completionSessionActive else { return false }

            let query = context.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return false }

            let suggestions = tabCompletionCandidates(for: context.query)
            guard !suggestions.isEmpty else { return false }

            completionSessionActive = true
            textView.complete(nil)
            return true
        }

        func handleTabCompletion() -> Bool {
            guard wikiAutocompleteEnabled,
                  let textView,
                  let context = pendingCompletionContext
            else { return false }

            let cursor = textView.selectedRange().location
            let textLength = (textView.string as NSString).length
            guard context.replacementRange.location >= 0,
                  NSMaxRange(context.replacementRange) <= textLength
            else { return false }
            // Safety invariant: for unclosed wiki links, never replace past cursor.
            guard context.hasClosingBrackets || NSMaxRange(context.replacementRange) <= cursor else {
                return false
            }

            let query = context.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return false }

            guard !completionSessionActive else { return false }

            let suggestions = tabCompletionCandidates(for: context.query)
            guard let first = suggestions.first else { return false }

            let hasExactMatch = suggestions.contains {
                $0.insertTarget.compare(query, options: .caseInsensitive) == .orderedSame
            }
            if suggestions.count > 1 && !hasExactMatch {
                completionSessionActive = true
                textView.complete(nil)
                return true
            }

            let selected = first.insertTarget.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selected.isEmpty else { return false }

            isApplyingCompletion = true
            defer { isApplyingCompletion = false }

            guard textView.shouldChangeText(in: context.replacementRange, replacementString: selected) else {
                return false
            }
            textView.textStorage?.replaceCharacters(in: context.replacementRange, with: selected)
            textView.didChangeText()

            var newCursor = context.replacementRange.location + (selected as NSString).length
            if !context.hasClosingBrackets {
                let close = "]]"
                textView.insertText(close, replacementRange: NSRange(location: newCursor, length: 0))
                newCursor += close.count
            }

            textView.setSelectedRange(NSRange(location: newCursor, length: 0))
            updateCompletionContext(for: textView)
            return true
        }

        private func tabCompletionCandidates(for query: String) -> [WikiLinkSuggestion] {
            let suggestions = wikiSuggestions(query)
            let lowerQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !lowerQuery.isEmpty else { return suggestions }

            let prefixOnly = suggestions.filter { $0.insertTarget.lowercased().hasPrefix(lowerQuery) }
            return prefixOnly.isEmpty ? suggestions : prefixOnly
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL,
                  let target = WikiLinkURLCodec.target(from: url) else {
                return false
            }

            let modifiers = NSApp.currentEvent?.modifierFlags ?? []
            guard modifiers.contains(.command) else {
                // Editor mode should only navigate on Cmd-click.
                return true
            }

            if let custom = textView as? CustomTextView {
                custom.onOpenWikiLink?(target)
                return true
            }
            return false
        }

        func textView(
            _ textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            guard wikiAutocompleteEnabled else { return [] }
            guard let context = pendingCompletionContext else {
                completionSessionActive = false
                return []
            }
            guard !context.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                completionSessionActive = false
                return []
            }

            let suggestions = tabCompletionCandidates(for: context.query)
            completionSessionActive = !suggestions.isEmpty
            guard !suggestions.isEmpty else { return [] }

            index?.pointee = 0
            return suggestions.map(\.insertTarget)
        }

        func textView(
            _ textView: NSTextView,
            insertCompletion word: String,
            forPartialWordRange charRange: NSRange,
            movement: Int,
            isFinal flag: Bool
        ) {
            guard wikiAutocompleteEnabled else { return }
            guard flag else { return }
            // Only accept explicit keyboard commits (return/tab). Ignore navigation moves.
            let allowedMovements: Set<Int> = [NSReturnTextMovement, NSTabTextMovement]
            guard allowedMovements.contains(movement) else { return }
            if let event = NSApp.currentEvent, event.type == .keyDown {
                // Defensive guard: never commit on arrow-key or other non-commit key events.
                guard event.keyCode == 36 || event.keyCode == 48 else { return }
            }
            guard let context = pendingCompletionContext else { return }
            let cursor = textView.selectedRange().location
            let textLength = (textView.string as NSString).length
            guard context.replacementRange.location >= 0,
                  NSMaxRange(context.replacementRange) <= textLength
            else { return }
            guard context.hasClosingBrackets || NSMaxRange(context.replacementRange) <= cursor else {
                return
            }
            let selected = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selected.isEmpty else { return }

            isApplyingCompletion = true
            defer { isApplyingCompletion = false }

            guard textView.shouldChangeText(in: context.replacementRange, replacementString: selected) else {
                return
            }
            textView.textStorage?.replaceCharacters(in: context.replacementRange, with: selected)
            textView.didChangeText()

            var newCursor = context.replacementRange.location + (selected as NSString).length
            if !context.hasClosingBrackets {
                let close = "]]"
                textView.insertText(close, replacementRange: NSRange(location: newCursor, length: 0))
                newCursor += close.count
            }

            textView.setSelectedRange(NSRange(location: newCursor, length: 0))
            pendingCompletionContext = nil
            completionSessionActive = false
            updateCompletionContext(for: textView)
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
    var refusesFocus: Bool = false
    override var acceptsFirstResponder: Bool { !refusesFocus }
    override var canBecomeKeyView: Bool { !refusesFocus && super.canBecomeKeyView }
    override func becomeFirstResponder() -> Bool {
        if refusesFocus { return false }
        if let docView = documentView {
            return window?.makeFirstResponder(docView) ?? false
        }
        return super.becomeFirstResponder()
    }
}

class CustomTextView: NSTextView {
    var onShiftTab: (() -> Void)?
    var onEscape: (() -> Void)?
    var onTabCompletion: (() -> Bool)?
    var onOpenCompletionList: (() -> Bool)?
    var onEscapeCompletion: (() -> Bool)?
    var onOpenWikiLink: ((String) -> Void)?
    var refusesFocus: Bool = false

    override var acceptsFirstResponder: Bool {
        refusesFocus ? false : super.acceptsFirstResponder
    }

    override var canBecomeKeyView: Bool {
        !refusesFocus && super.canBecomeKeyView
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == [.command, .shift],
           let chars = event.charactersIgnoringModifiers, chars.lowercased() == "d" {
            insertCurrentDate()
            return true
        }
        if flags == [.command],
           event.keyCode == 47 {
            insertCurrentDate()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 48 && flags.contains(.shift) {
            window?.makeFirstResponder(nil)
            onShiftTab?()
            return
        }
        if event.keyCode == 48 && flags.isEmpty {
            if onTabCompletion?() == true {
                return
            }
        }
        if event.keyCode == 125 && flags.isEmpty {
            if onOpenCompletionList?() == true {
                return
            }
        }

        if event.keyCode == 53 {
            if onEscapeCompletion?() == true {
                return
            }
            if let scrollView = enclosingScrollView, scrollView.isFindBarVisible {
                let menuItem = NSMenuItem()
                menuItem.tag = Int(NSTextFinder.Action.hideFindInterface.rawValue)
                performTextFinderAction(menuItem)
                return
            }
            window?.makeFirstResponder(nil)
            onEscape?()
            return
        }
        
        super.keyDown(with: event)
    }

    private func insertCurrentDate() {
        let formatter = DateFormatter()
        formatter.dateFormat = "[yyyy-MM-dd EEE HH:mm]"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let dateString = formatter.string(from: Date())
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
    PlainTextEditor(text: .constant("Hello, neonv!\n\nThis is plain text."),
                    cursorPosition: .constant(0), scrollFraction: .constant(0))
        .frame(width: 400, height: 300)
}
