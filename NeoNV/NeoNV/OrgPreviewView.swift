import SwiftUI
import AppKit

struct OrgPreviewView: NSViewRepresentable {
    var content: String
    var fontSize: CGFloat = 13
    var onShiftTab: (() -> Void)?
    var onTypeToEdit: (() -> Void)?
    var existingNoteNames: Set<String> = []
    var onWikiLinkClicked: ((String) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = FocusForwardingScrollView()
        let textView = PreviewTextView()

        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.autoresizingMask = [.width, .height]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        textView.onShiftTab = onShiftTab
        textView.onTypeToEdit = onTypeToEdit
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        updateContent(textView: textView, content: content, fontSize: fontSize)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PreviewTextView else { return }

        textView.onShiftTab = onShiftTab
        textView.onTypeToEdit = onTypeToEdit
        textView.delegate = context.coordinator

        updateContent(textView: textView, content: content, fontSize: fontSize)
    }

    private func updateContent(textView: NSTextView, content: String, fontSize: CGFloat) {
        let attributedString = parseOrg(content: content, fontSize: fontSize)
        textView.textStorage?.setAttributedString(attributedString)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onWikiLinkClicked: onWikiLinkClicked)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onWikiLinkClicked: ((String) -> Void)?

        init(onWikiLinkClicked: ((String) -> Void)?) {
            self.onWikiLinkClicked = onWikiLinkClicked
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            WikiLinkHelper.handleClickedLink(link, onWikiLinkClicked: onWikiLinkClicked)
        }
    }
}

// MARK: - Org Parser

private enum BlockState {
    case none
    case quote
    case example
    case src
}

private struct OrgParserContext {
    let fontSize: CGFloat
    let baseFont: NSFont
    let monoFont: NSFont
    let boldFont: NSFont
    let italicFont: NSFont
    let textColor: NSColor
    let secondaryColor: NSColor
    let codeBackground: NSColor

    let todoColors: [String: NSColor] = [
        "TODO": .systemOrange,
        "DONE": .systemGreen,
        "NEXT": .systemBlue,
        "WAITING": .systemYellow,
        "CANCELLED": .systemRed
    ]

    init(fontSize: CGFloat) {
        self.fontSize = fontSize
        self.baseFont = NSFont.systemFont(ofSize: fontSize)
        self.monoFont = NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)
        self.boldFont = NSFont.boldSystemFont(ofSize: fontSize)
        self.italicFont = NSFont.systemFont(ofSize: fontSize).withTraits(.italicFontMask)
        self.textColor = NSColor.textColor
        self.secondaryColor = NSColor.secondaryLabelColor
        self.codeBackground = NSColor.quaternaryLabelColor
    }

    var baseAttrs: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: textColor]
    }
}

extension OrgPreviewView {
    private func parseOrg(content: String, fontSize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = content.components(separatedBy: "\n")
        let ctx = OrgParserContext(fontSize: fontSize)

        appendTitle(from: lines, to: result, ctx: ctx)

        var blockState = BlockState.none
        var blockContent = ""

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let upperTrimmed = trimmed.uppercased()
            let isLastLine = index >= lines.count - 1

            if upperTrimmed.hasPrefix("#+TITLE:") {
                continue
            }

            if let newState = handleBlockDelimiter(
                upperTrimmed: upperTrimmed,
                currentState: blockState,
                blockContent: &blockContent,
                result: result,
                ctx: ctx,
                isLastLine: isLastLine
            ) {
                blockState = newState
                continue
            }

            if blockState != .none {
                blockContent += line + "\n"
                continue
            }

            if shouldSkipMetadataLine(trimmed) {
                continue
            }

            if appendCommentLine(trimmed: trimmed, line: line, to: result, ctx: ctx, isLastLine: isLastLine) {
                continue
            }

            var lineAttrs = ctx.baseAttrs
            applyDoneFormatting(to: &lineAttrs, line: line, ctx: ctx)

            if appendHeaderLine(line: line, to: result, ctx: ctx, lineAttrs: lineAttrs, isLastLine: isLastLine) {
                continue
            }

            if appendTableLine(trimmed: trimmed, to: result, ctx: ctx, isLastLine: isLastLine) {
                continue
            }

            if appendDefinitionList(
                trimmed: trimmed, to: result, ctx: ctx, lineAttrs: lineAttrs, isLastLine: isLastLine
            ) {
                continue
            }

            if appendUnorderedList(
                trimmed: trimmed, line: line, to: result, ctx: ctx, lineAttrs: lineAttrs, isLastLine: isLastLine
            ) {
                continue
            }

            if appendOrderedList(
                trimmed: trimmed, line: line, to: result, ctx: ctx, lineAttrs: lineAttrs, isLastLine: isLastLine
            ) {
                continue
            }

            let attrLine = processOrgInlineFormatting(line, baseAttrs: lineAttrs, ctx: ctx)
            result.append(attrLine)
            if !isLastLine {
                result.append(NSAttributedString(string: "\n", attributes: lineAttrs))
            }
        }

        appendUnclosedBlock(blockState: blockState, blockContent: blockContent, to: result, ctx: ctx)

        return result
    }

    // MARK: - Title

    private func appendTitle(
        from lines: [String],
        to result: NSMutableAttributedString,
        ctx: OrgParserContext
    ) {
        guard let titleLine = lines.first(where: {
            $0.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("#+TITLE:")
        }) else { return }

        let trimmedTitleLine = titleLine.trimmingCharacters(in: .whitespaces)
        let titleContent = String(trimmedTitleLine.dropFirst(8)).trimmingCharacters(in: .whitespaces)

        guard !titleContent.isEmpty else { return }

        let titleSize = ctx.fontSize + 10
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: titleSize, weight: .bold),
            .foregroundColor: ctx.textColor
        ]

        result.append(NSAttributedString(string: titleContent, attributes: titleAttrs))
        result.append(NSAttributedString(string: "\n\n", attributes: [.font: ctx.baseFont]))
    }

    // MARK: - Block Handling

    private func handleBlockDelimiter(
        upperTrimmed: String,
        currentState: BlockState,
        blockContent: inout String,
        result: NSMutableAttributedString,
        ctx: OrgParserContext,
        isLastLine: Bool
    ) -> BlockState? {
        if upperTrimmed.hasPrefix("#+BEGIN_QUOTE") {
            return .quote
        }
        if upperTrimmed.hasPrefix("#+END_QUOTE") {
            appendQuoteBlock(blockContent, to: result, ctx: ctx, isLastLine: isLastLine)
            blockContent = ""
            return BlockState.none
        }
        if upperTrimmed.hasPrefix("#+BEGIN_EXAMPLE") || upperTrimmed.hasPrefix("#+BEGIN_SRC") {
            return upperTrimmed.contains("EXAMPLE") ? .example : .src
        }
        if upperTrimmed.hasPrefix("#+END_EXAMPLE") || upperTrimmed.hasPrefix("#+END_SRC") {
            appendCodeBlock(blockContent, to: result, ctx: ctx)
            blockContent = ""
            return BlockState.none
        }
        return nil
    }

    private func appendQuoteBlock(
        _ content: String,
        to result: NSMutableAttributedString,
        ctx: OrgParserContext,
        isLastLine: Bool
    ) {
        guard !content.isEmpty else { return }
        let quoteAttrs: [NSAttributedString.Key: Any] = [
            .font: ctx.italicFont,
            .foregroundColor: ctx.secondaryColor
        ]
        let quoteLine = "  │ " + content.trimmingCharacters(in: .newlines)
        result.append(NSAttributedString(string: quoteLine, attributes: quoteAttrs))
        if !isLastLine {
            result.append(NSAttributedString(string: "\n", attributes: quoteAttrs))
        }
    }

    private func appendCodeBlock(_ content: String, to result: NSMutableAttributedString, ctx: OrgParserContext) {
        guard !content.isEmpty else { return }
        let codeAttrs: [NSAttributedString.Key: Any] = [
            .font: ctx.monoFont,
            .foregroundColor: ctx.textColor,
            .backgroundColor: ctx.codeBackground
        ]
        result.append(NSAttributedString(string: content, attributes: codeAttrs))
    }

    private func appendUnclosedBlock(
        blockState: BlockState,
        blockContent: String,
        to result: NSMutableAttributedString,
        ctx: OrgParserContext
    ) {
        guard blockState != .none, !blockContent.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: ctx.monoFont,
            .foregroundColor: ctx.textColor,
            .backgroundColor: ctx.codeBackground
        ]
        result.append(NSAttributedString(string: blockContent, attributes: attrs))
    }

    // MARK: - Line Type Detection

    private func shouldSkipMetadataLine(_ trimmed: String) -> Bool {
        let upper = trimmed.uppercased()
        return trimmed.hasPrefix("#+") && !upper.hasPrefix("#+BEGIN") && !upper.hasPrefix("#+END")
    }

    private func appendCommentLine(
        trimmed: String,
        line: String,
        to result: NSMutableAttributedString,
        ctx: OrgParserContext,
        isLastLine: Bool
    ) -> Bool {
        guard trimmed.hasPrefix("# ") else { return false }
        let commentAttrs: [NSAttributedString.Key: Any] = [
            .font: ctx.baseFont,
            .foregroundColor: ctx.secondaryColor
        ]
        result.append(NSAttributedString(string: line, attributes: commentAttrs))
        if !isLastLine {
            result.append(NSAttributedString(string: "\n", attributes: commentAttrs))
        }
        return true
    }

    private func applyDoneFormatting(
        to attrs: inout [NSAttributedString.Key: Any],
        line: String,
        ctx: OrgParserContext
    ) {
        let isDone = line.contains("@done") || line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ")
        if isDone {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attrs[.strikethroughColor] = ctx.secondaryColor
            attrs[.foregroundColor] = ctx.secondaryColor
        }
    }

    // MARK: - Headers

    private func appendHeaderLine(
        line: String,
        to result: NSMutableAttributedString,
        ctx: OrgParserContext,
        lineAttrs: [NSAttributedString.Key: Any],
        isLastLine: Bool
    ) -> Bool {
        guard let headerMatch = line.range(of: "^(\\*{1,8})\\s+(.*)$", options: .regularExpression) else {
            return false
        }

        let headerText = String(line[headerMatch])
        let stars = headerText.prefix(while: { $0 == "*" })
        let level = stars.count
        let headerContent = String(headerText.dropFirst(level)).trimmingCharacters(in: .whitespaces)

        let headerSize = ctx.fontSize + CGFloat(max(0, 12 - level * 2))
        let headerWeight: NSFont.Weight = level <= 2 ? .bold : .semibold
        var headerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: headerSize, weight: headerWeight),
            .foregroundColor: ctx.textColor
        ]

        var displayContent = headerContent
        for (keyword, color) in ctx.todoColors {
            if headerContent.hasPrefix(keyword + " ") || headerContent == keyword {
                appendTodoHeader(
                    keyword: keyword,
                    color: color,
                    headerContent: headerContent,
                    headerSize: headerSize,
                    headerWeight: headerWeight,
                    headerAttrs: &headerAttrs,
                    to: result,
                    ctx: ctx,
                    isLastLine: isLastLine
                )
                displayContent = ""
                break
            }
        }

        if !displayContent.isEmpty {
            result.append(NSAttributedString(string: displayContent, attributes: headerAttrs))
            if !isLastLine {
                result.append(NSAttributedString(string: "\n", attributes: headerAttrs))
            }
        }
        return true
    }

    private func appendTodoHeader(
        keyword: String,
        color: NSColor,
        headerContent: String,
        headerSize: CGFloat,
        headerWeight: NSFont.Weight,
        headerAttrs: inout [NSAttributedString.Key: Any],
        to result: NSMutableAttributedString,
        ctx: OrgParserContext,
        isLastLine: Bool
    ) {
        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: headerSize - 2, weight: .bold),
            .foregroundColor: NSColor.white,
            .backgroundColor: color
        ]
        let restText = String(headerContent.dropFirst(keyword.count))
        result.append(NSAttributedString(string: " \(keyword)", attributes: badgeAttrs))
        headerAttrs[.font] = NSFont.systemFont(ofSize: headerSize, weight: headerWeight)
        result.append(NSAttributedString(string: restText, attributes: headerAttrs))
        if !isLastLine {
            result.append(NSAttributedString(string: "\n", attributes: headerAttrs))
        }
    }

    // MARK: - Tables

    private func appendTableLine(
        trimmed: String,
        to result: NSMutableAttributedString,
        ctx: OrgParserContext,
        isLastLine: Bool
    ) -> Bool {
        guard trimmed.hasPrefix("|") else { return false }

        let tableAttrs: [NSAttributedString.Key: Any] = [
            .font: ctx.monoFont,
            .foregroundColor: ctx.textColor
        ]

        if trimmed.range(of: "^\\|[-+]+\\|?$", options: .regularExpression) != nil {
            let sepAttrs: [NSAttributedString.Key: Any] = [
                .font: ctx.monoFont,
                .foregroundColor: ctx.secondaryColor
            ]
            let rule = String(repeating: "─", count: min(trimmed.count, 60))
            result.append(NSAttributedString(string: rule, attributes: sepAttrs))
        } else {
            result.append(NSAttributedString(string: trimmed, attributes: tableAttrs))
        }

        if !isLastLine {
            result.append(NSAttributedString(string: "\n", attributes: tableAttrs))
        }
        return true
    }

    // MARK: - Lists

    private func appendDefinitionList(
        trimmed: String,
        to result: NSMutableAttributedString,
        ctx: OrgParserContext,
        lineAttrs: [NSAttributedString.Key: Any],
        isLastLine: Bool
    ) -> Bool {
        guard let defMatch = trimmed.range(of: "^\\s*-\\s+.+\\s+::\\s+", options: .regularExpression) else {
            return false
        }

        let matchStr = String(trimmed[defMatch])
        guard let colonRange = matchStr.range(of: " :: ") else { return false }

        let beforeColon = matchStr[matchStr.startIndex..<colonRange.lowerBound]
        let term = String(beforeColon).replacingOccurrences(
            of: "^\\s*-\\s+", with: "", options: .regularExpression
        )
        let desc = String(matchStr[colonRange.upperBound...])

        result.append(NSAttributedString(string: "  ", attributes: lineAttrs))

        let termAttrs: [NSAttributedString.Key: Any] = [
            .font: ctx.boldFont,
            .foregroundColor: ctx.textColor
        ]
        result.append(NSAttributedString(string: term, attributes: termAttrs))
        result.append(NSAttributedString(string: " — ", attributes: lineAttrs))

        let descAttr = processOrgInlineFormatting(desc, baseAttrs: lineAttrs, ctx: ctx)
        result.append(descAttr)

        if !isLastLine {
            result.append(NSAttributedString(string: "\n", attributes: lineAttrs))
        }
        return true
    }

    private func appendUnorderedList(
        trimmed: String,
        line: String,
        to result: NSMutableAttributedString,
        ctx: OrgParserContext,
        lineAttrs: [NSAttributedString.Key: Any],
        isLastLine: Bool
    ) -> Bool {
        guard trimmed.range(of: "^\\s*[-+]\\s+", options: .regularExpression) != nil else {
            return false
        }

        let indentCount = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let indent = String(repeating: " ", count: indentCount)
        let content = trimmed.replacingOccurrences(of: "^[-+]\\s+", with: "", options: .regularExpression)
        let bulletLine = indent + "  • " + content

        let attrLine = processOrgInlineFormatting(bulletLine, baseAttrs: lineAttrs, ctx: ctx)
        result.append(attrLine)

        if !isLastLine {
            result.append(NSAttributedString(string: "\n", attributes: lineAttrs))
        }
        return true
    }

    private func appendOrderedList(
        trimmed: String,
        line: String,
        to result: NSMutableAttributedString,
        ctx: OrgParserContext,
        lineAttrs: [NSAttributedString.Key: Any],
        isLastLine: Bool
    ) -> Bool {
        guard let orderedMatch = trimmed.range(
            of: "^\\s*(\\d+)[.)]+\\s+(.*)", options: .regularExpression
        ) else {
            return false
        }

        let matchStr = String(trimmed[orderedMatch])
        let indentCount = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let indent = String(repeating: " ", count: indentCount)

        let numEnd = matchStr.firstIndex(where: { $0 == "." || $0 == ")" }) ?? matchStr.startIndex
        let num = String(matchStr[matchStr.startIndex..<numEnd]).trimmingCharacters(in: .whitespaces)
        let restStart = matchStr.index(after: numEnd)
        let rest = String(matchStr[restStart...]).trimmingCharacters(in: .whitespaces)
        let orderedLine = indent + "  \(num). " + rest

        let attrLine = processOrgInlineFormatting(orderedLine, baseAttrs: lineAttrs, ctx: ctx)
        result.append(attrLine)

        if !isLastLine {
            result.append(NSAttributedString(string: "\n", attributes: lineAttrs))
        }
        return true
    }

    // MARK: - Inline Formatting

    private func processOrgInlineFormatting(
        _ text: String,
        baseAttrs: [NSAttributedString.Key: Any],
        ctx: OrgParserContext
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var remaining = text
        let currentAttrs = baseAttrs

        let patterns = buildInlinePatterns(ctx: ctx)

        while !remaining.isEmpty {
            var earliestRange: Range<String.Index>?
            var earliestPatternIndex: Int?

            for (i, pattern) in patterns.enumerated() {
                if let range = remaining.range(of: pattern.regex, options: .regularExpression) {
                    if earliestRange == nil || range.lowerBound < earliestRange!.lowerBound {
                        earliestRange = range
                        earliestPatternIndex = i
                    }
                }
            }

            guard let matchRange = earliestRange, let patIdx = earliestPatternIndex else {
                result.append(NSAttributedString(string: remaining, attributes: currentAttrs))
                break
            }

            let before = String(remaining[..<matchRange.lowerBound])
            if !before.isEmpty {
                result.append(NSAttributedString(string: before, attributes: currentAttrs))
            }

            let matchText = String(remaining[matchRange])
            let formatted = patterns[patIdx].handler(matchText, currentAttrs)
            result.append(formatted)

            remaining = String(remaining[matchRange.upperBound...])
        }

        return result
    }

    private typealias InlinePattern = (
        regex: String,
        handler: (String, [NSAttributedString.Key: Any]) -> NSAttributedString
    )

    private func buildInlinePatterns(ctx: OrgParserContext) -> [InlinePattern] {
        [
            ("\\[\\[([^\\]]+?)\\](?:\\[([^\\]]+?)\\])?\\]", { match, attrs in
                self.formatOrgLink(match, attrs: attrs)
            }),
            ("[<\\[]\\d{4}-\\d{2}-\\d{2}[^>\\]]*?[>\\]]" +
             "(?:--[<\\[]\\d{4}-\\d{2}-\\d{2}[^>\\]]*?[>\\]])?", { match, attrs in
                self.formatTimestamp(match, attrs: attrs)
            }),
            ("~([^~]+?)~", { match, attrs in
                self.formatCode(match, attrs: attrs, background: ctx.codeBackground)
            }),
            ("=([^=]+?)=", { match, attrs in
                self.formatVerbatim(match, attrs: attrs)
            }),
            ("(?<![\\w*])\\*([^*]+?)\\*(?![\\w*])", { match, attrs in
                self.formatBold(match, attrs: attrs, font: ctx.boldFont)
            }),
            ("(?<![\\w/])/([^/]+?)/(?![\\w/])", { match, attrs in
                self.formatItalic(match, attrs: attrs, font: ctx.italicFont)
            }),
            ("(?<![\\w+])\\+([^+]+?)\\+(?![\\w+])", { match, attrs in
                self.formatStrikethrough(match, attrs: attrs)
            })
        ]
    }

    private func formatOrgLink(_ match: String, attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
        var linkAttrs = attrs
        let inner = String(match.dropFirst(2).dropLast(2))
        let displayText: String
        let urlText: String
        if let sepRange = inner.range(of: "][") {
            urlText = String(inner[inner.startIndex..<sepRange.lowerBound])
            displayText = String(inner[sepRange.upperBound...])
        } else {
            urlText = inner
            displayText = inner
        }
        let parsedURL = URL(string: urlText)
        let hasScheme = parsedURL?.scheme != nil

        if hasScheme, let url = parsedURL {
            linkAttrs[.foregroundColor] = NSColor.linkColor
            linkAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            linkAttrs[.link] = url
        } else {
            let lower = urlText.lowercased()
            let exists = existingNoteNames.contains(lower)
            let color = exists ? NSColor.systemBlue : NSColor.systemOrange
            linkAttrs[.foregroundColor] = color
            linkAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            linkAttrs[.underlineColor] = color
            if let url = WikiLinkHelper.wikiLinkURL(for: urlText) {
                linkAttrs[.link] = url
            }
        }
        return NSAttributedString(string: displayText, attributes: linkAttrs)
    }

    private func formatTimestamp(_ match: String, attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
        var tsAttrs = attrs
        tsAttrs[.font] = monoFontForSize(attrs)
        tsAttrs[.foregroundColor] = NSColor.secondaryLabelColor
        return NSAttributedString(string: match, attributes: tsAttrs)
    }

    private func formatCode(
        _ match: String,
        attrs: [NSAttributedString.Key: Any],
        background: NSColor
    ) -> NSAttributedString {
        var codeAttrs = attrs
        let inner = String(match.dropFirst().dropLast())
        codeAttrs[.font] = monoFontForSize(attrs)
        codeAttrs[.backgroundColor] = background
        return NSAttributedString(string: inner, attributes: codeAttrs)
    }

    private func formatVerbatim(_ match: String, attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
        var verbAttrs = attrs
        let inner = String(match.dropFirst().dropLast())
        verbAttrs[.font] = monoFontForSize(attrs)
        return NSAttributedString(string: inner, attributes: verbAttrs)
    }

    private func formatBold(
        _ match: String,
        attrs: [NSAttributedString.Key: Any],
        font: NSFont
    ) -> NSAttributedString {
        var boldAttrs = attrs
        let inner = String(match.dropFirst().dropLast())
        boldAttrs[.font] = font
        return NSAttributedString(string: inner, attributes: boldAttrs)
    }

    private func formatItalic(
        _ match: String,
        attrs: [NSAttributedString.Key: Any],
        font: NSFont
    ) -> NSAttributedString {
        var italAttrs = attrs
        let inner = String(match.dropFirst().dropLast())
        italAttrs[.font] = font
        return NSAttributedString(string: inner, attributes: italAttrs)
    }

    private func formatStrikethrough(
        _ match: String, attrs: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        var strikeAttrs = attrs
        let inner = String(match.dropFirst().dropLast())
        strikeAttrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        return NSAttributedString(string: inner, attributes: strikeAttrs)
    }

    private func monoFontForSize(_ attrs: [NSAttributedString.Key: Any]) -> NSFont {
        let size = (attrs[.font] as? NSFont)?.pointSize ?? 12
        return NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular)
    }
}

// MARK: - Focus Forwarding

private class FocusForwardingScrollView: NSScrollView {
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        if let docView = documentView {
            return window?.makeFirstResponder(docView) ?? false
        }
        return super.becomeFirstResponder()
    }
}

#Preview {
    OrgPreviewView(content: """
    #+TITLE: My Org Document

    * Header 1
    ** Header 2 TODO Fix this
    *** Header 3

    - Item one
    - Item two
    + Item three

    1. First
    2. Second

    - Term :: Description here

    | Name  | Value |
    |-------+-------|
    | foo   | 42    |

    [[https://example.com][Example Link]]

    <2026-01-28 Tue>

    This has *bold*, /italic/, ~code~, =verbatim=, and +strikethrough+.

    #+BEGIN_QUOTE
    A wise quote here.
    #+END_QUOTE

    #+BEGIN_SRC python
    def hello():
        print("world")
    #+END_SRC

    * TODO Buy groceries
    * DONE Write parser
    * NEXT Review PR
    """)
    .frame(width: 400, height: 600)
}
