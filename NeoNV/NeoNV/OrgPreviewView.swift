import SwiftUI
import AppKit

struct OrgPreviewView: NSViewRepresentable {
    var content: String
    var fontSize: CGFloat = 13
    var onShiftTab: (() -> Void)?
    var onTypeToEdit: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
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

        updateContent(textView: textView, content: content, fontSize: fontSize)
    }

    private func updateContent(textView: NSTextView, content: String, fontSize: CGFloat) {
        let attributedString = parseOrg(content: content, fontSize: fontSize)
        textView.textStorage?.setAttributedString(attributedString)
    }

    // MARK: - Org Parser

    private enum BlockState {
        case none
        case quote
        case example
        case src
    }

    private func parseOrg(content: String, fontSize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = content.components(separatedBy: "\n")

        let baseFont = NSFont.systemFont(ofSize: fontSize)
        let monoFont = NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)
        let boldFont = NSFont.boldSystemFont(ofSize: fontSize)
        let italicFont = NSFont.systemFont(ofSize: fontSize).withTraits(.italicFontMask)
        let textColor = NSColor.textColor
        let secondaryColor = NSColor.secondaryLabelColor
        let codeBackground = NSColor.quaternaryLabelColor

        let todoColors: [String: NSColor] = [
            "TODO": .systemOrange,
            "DONE": .systemGreen,
            "NEXT": .systemBlue,
            "WAITING": .systemYellow,
            "CANCELLED": .systemRed
        ]

        var blockState = BlockState.none
        var blockContent = ""

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let upperTrimmed = trimmed.uppercased()

            // Block begin/end
            if upperTrimmed.hasPrefix("#+BEGIN_QUOTE") {
                blockState = .quote
                continue
            }
            if upperTrimmed.hasPrefix("#+END_QUOTE") {
                if !blockContent.isEmpty {
                    let quoteAttrs: [NSAttributedString.Key: Any] = [
                        .font: italicFont,
                        .foregroundColor: secondaryColor
                    ]
                    let quoteLine = "  │ " + blockContent.trimmingCharacters(in: .newlines)
                    result.append(NSAttributedString(string: quoteLine, attributes: quoteAttrs))
                    if index < lines.count - 1 {
                        result.append(NSAttributedString(string: "\n", attributes: quoteAttrs))
                    }
                }
                blockContent = ""
                blockState = .none
                continue
            }
            if upperTrimmed.hasPrefix("#+BEGIN_EXAMPLE") || upperTrimmed.hasPrefix("#+BEGIN_SRC") {
                blockState = upperTrimmed.contains("EXAMPLE") ? .example : .src
                continue
            }
            if upperTrimmed.hasPrefix("#+END_EXAMPLE") || upperTrimmed.hasPrefix("#+END_SRC") {
                if !blockContent.isEmpty {
                    let codeAttrs: [NSAttributedString.Key: Any] = [
                        .font: monoFont,
                        .foregroundColor: textColor,
                        .backgroundColor: codeBackground
                    ]
                    result.append(NSAttributedString(string: blockContent, attributes: codeAttrs))
                }
                blockContent = ""
                blockState = .none
                continue
            }

            // Accumulate block content
            if blockState != .none {
                blockContent += line + "\n"
                continue
            }

            // Comments: lines starting with "# " or "#+" (non-block directives)
            if trimmed.hasPrefix("# ") || (trimmed.hasPrefix("#+") && !trimmed.uppercased().hasPrefix("#+BEGIN") && !trimmed.uppercased().hasPrefix("#+END")) {
                let commentAttrs: [NSAttributedString.Key: Any] = [
                    .font: baseFont,
                    .foregroundColor: secondaryColor
                ]
                result.append(NSAttributedString(string: line, attributes: commentAttrs))
                if index < lines.count - 1 {
                    result.append(NSAttributedString(string: "\n", attributes: commentAttrs))
                }
                continue
            }

            let baseAttrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: textColor
            ]

            // Headers: * H1 through ******** H8
            if let headerMatch = line.range(of: "^(\\*{1,8})\\s+(.*)$", options: .regularExpression) {
                let headerText = String(line[headerMatch])
                let stars = headerText.prefix(while: { $0 == "*" })
                let level = stars.count
                let headerContent = String(headerText.dropFirst(level)).trimmingCharacters(in: .whitespaces)

                let headerSize = fontSize + CGFloat(max(0, 12 - level * 2))
                let headerWeight: NSFont.Weight = level <= 2 ? .bold : .semibold
                var headerAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: headerSize, weight: headerWeight),
                    .foregroundColor: textColor
                ]

                // Check for TODO keywords
                var displayContent = headerContent
                for (keyword, color) in todoColors {
                    if headerContent.hasPrefix(keyword + " ") || headerContent == keyword {
                        // Build attributed string with colored keyword badge
                        let badgeAttrs: [NSAttributedString.Key: Any] = [
                            .font: NSFont.systemFont(ofSize: headerSize - 2, weight: .bold),
                            .foregroundColor: NSColor.white,
                            .backgroundColor: color
                        ]
                        let restText = String(headerContent.dropFirst(keyword.count))
                        result.append(NSAttributedString(string: " \(keyword)", attributes: badgeAttrs))
                        headerAttrs[.font] = NSFont.systemFont(ofSize: headerSize, weight: headerWeight)
                        result.append(NSAttributedString(string: restText, attributes: headerAttrs))
                        if index < lines.count - 1 {
                            result.append(NSAttributedString(string: "\n", attributes: headerAttrs))
                        }
                        displayContent = ""
                        break
                    }
                }

                if !displayContent.isEmpty {
                    result.append(NSAttributedString(string: displayContent, attributes: headerAttrs))
                    if index < lines.count - 1 {
                        result.append(NSAttributedString(string: "\n", attributes: headerAttrs))
                    }
                }
                continue
            }

            // Table lines
            if trimmed.hasPrefix("|") {
                // Table separator
                if trimmed.range(of: "^\\|[-+]+\\|?$", options: .regularExpression) != nil {
                    let sepAttrs: [NSAttributedString.Key: Any] = [
                        .font: monoFont,
                        .foregroundColor: secondaryColor
                    ]
                    let rule = String(repeating: "─", count: min(trimmed.count, 60))
                    result.append(NSAttributedString(string: rule, attributes: sepAttrs))
                } else {
                    let tableAttrs: [NSAttributedString.Key: Any] = [
                        .font: monoFont,
                        .foregroundColor: textColor
                    ]
                    result.append(NSAttributedString(string: line, attributes: tableAttrs))
                }
                if index < lines.count - 1 {
                    result.append(NSAttributedString(string: "\n", attributes: baseAttrs))
                }
                continue
            }

            // Descriptive list: - Term :: Description
            if let descMatch = trimmed.range(of: "^\\s*-\\s+(.+?)\\s*::\\s*(.*)", options: .regularExpression) {
                let matchStr = String(trimmed[descMatch])
                // Parse out term and description
                if let colonRange = matchStr.range(of: " :: ") {
                    let beforeColon = matchStr[matchStr.startIndex..<colonRange.lowerBound]
                    let term = String(beforeColon).replacingOccurrences(of: "^\\s*-\\s+", with: "", options: .regularExpression)
                    let desc = String(matchStr[colonRange.upperBound...])

                    let indent = "  "
                    result.append(NSAttributedString(string: indent, attributes: baseAttrs))
                    let termAttrs: [NSAttributedString.Key: Any] = [
                        .font: boldFont,
                        .foregroundColor: textColor
                    ]
                    result.append(NSAttributedString(string: term, attributes: termAttrs))
                    result.append(NSAttributedString(string: " — ", attributes: baseAttrs))
                    let descAttr = processOrgInlineFormatting(desc, baseAttrs: baseAttrs, boldFont: boldFont, italicFont: italicFont, monoFont: monoFont, codeBackground: codeBackground)
                    result.append(descAttr)
                    if index < lines.count - 1 {
                        result.append(NSAttributedString(string: "\n", attributes: baseAttrs))
                    }
                    continue
                }
            }

            // Unordered list: - or +
            if trimmed.range(of: "^\\s*[-+]\\s+", options: .regularExpression) != nil {
                let indent = String(repeating: " ", count: line.prefix(while: { $0 == " " || $0 == "\t" }).count)
                let content = trimmed.replacingOccurrences(of: "^[-+]\\s+", with: "", options: .regularExpression)
                let bulletLine = indent + "  • " + content
                let attrLine = processOrgInlineFormatting(bulletLine, baseAttrs: baseAttrs, boldFont: boldFont, italicFont: italicFont, monoFont: monoFont, codeBackground: codeBackground)
                result.append(attrLine)
                if index < lines.count - 1 {
                    result.append(NSAttributedString(string: "\n", attributes: baseAttrs))
                }
                continue
            }

            // Ordered list: 1. or 1)
            if let orderedMatch = trimmed.range(of: "^\\s*(\\d+)[.)]+\\s+(.*)", options: .regularExpression) {
                let matchStr = String(trimmed[orderedMatch])
                let indent = String(repeating: " ", count: line.prefix(while: { $0 == " " || $0 == "\t" }).count)
                // Extract number and content
                let numEnd = matchStr.firstIndex(where: { $0 == "." || $0 == ")" }) ?? matchStr.startIndex
                let num = String(matchStr[matchStr.startIndex..<numEnd]).trimmingCharacters(in: .whitespaces)
                let restStart = matchStr.index(after: numEnd)
                let rest = String(matchStr[restStart...]).trimmingCharacters(in: .whitespaces)
                let orderedLine = indent + "  \(num). " + rest
                let attrLine = processOrgInlineFormatting(orderedLine, baseAttrs: baseAttrs, boldFont: boldFont, italicFont: italicFont, monoFont: monoFont, codeBackground: codeBackground)
                result.append(attrLine)
                if index < lines.count - 1 {
                    result.append(NSAttributedString(string: "\n", attributes: baseAttrs))
                }
                continue
            }

            // Regular line — process inline formatting
            let attrLine = processOrgInlineFormatting(line, baseAttrs: baseAttrs, boldFont: boldFont, italicFont: italicFont, monoFont: monoFont, codeBackground: codeBackground)
            result.append(attrLine)
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: baseAttrs))
            }
        }

        // Handle unclosed blocks
        if blockState != .none && !blockContent.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: monoFont,
                .foregroundColor: textColor,
                .backgroundColor: codeBackground
            ]
            result.append(NSAttributedString(string: blockContent, attributes: attrs))
        }

        return result
    }

    // MARK: - Inline Formatting

    private func processOrgInlineFormatting(
        _ text: String,
        baseAttrs: [NSAttributedString.Key: Any],
        boldFont: NSFont,
        italicFont: NSFont,
        monoFont: NSFont,
        codeBackground: NSColor
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var remaining = text
        let currentAttrs = baseAttrs

        // Patterns tried in priority order
        let patterns: [(regex: String, handler: (String, [NSAttributedString.Key: Any]) -> NSAttributedString)] = [
            // Org links [[url][desc]] or [[url]]
            ("\\[\\[([^\\]]+?)\\](?:\\[([^\\]]+?)\\])?\\]", { match, attrs in
                var linkAttrs = attrs
                // Parse link parts
                let inner = String(match.dropFirst(2).dropLast(2)) // remove [[ and ]]
                let displayText: String
                let urlText: String
                if let sepRange = inner.range(of: "][") {
                    urlText = String(inner[inner.startIndex..<sepRange.lowerBound])
                    displayText = String(inner[sepRange.upperBound...])
                } else {
                    urlText = inner
                    displayText = inner
                }
                linkAttrs[.foregroundColor] = NSColor.linkColor
                linkAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                if let url = URL(string: urlText) {
                    linkAttrs[.link] = url
                }
                return NSAttributedString(string: displayText, attributes: linkAttrs)
            }),
            // Timestamps <2026-01-28 Tue> or [2026-01-28 Tue] or ranges
            ("[<\\[]\\d{4}-\\d{2}-\\d{2}[^>\\]]*?[>\\]](?:--[<\\[]\\d{4}-\\d{2}-\\d{2}[^>\\]]*?[>\\]])?", { match, attrs in
                var tsAttrs = attrs
                tsAttrs[.font] = self.monoFontForSize(attrs)
                tsAttrs[.foregroundColor] = NSColor.secondaryLabelColor
                return NSAttributedString(string: match, attributes: tsAttrs)
            }),
            // Code ~text~
            ("~([^~]+?)~", { match, attrs in
                var codeAttrs = attrs
                let inner = String(match.dropFirst().dropLast())
                codeAttrs[.font] = self.monoFontForSize(attrs)
                codeAttrs[.backgroundColor] = codeBackground
                return NSAttributedString(string: inner, attributes: codeAttrs)
            }),
            // Verbatim =text=
            ("=([^=]+?)=", { match, attrs in
                var verbAttrs = attrs
                let inner = String(match.dropFirst().dropLast())
                verbAttrs[.font] = self.monoFontForSize(attrs)
                return NSAttributedString(string: inner, attributes: verbAttrs)
            }),
            // Bold *text*
            ("(?<![\\w*])\\*([^*]+?)\\*(?![\\w*])", { match, attrs in
                var boldAttrs = attrs
                let inner = String(match.dropFirst().dropLast())
                boldAttrs[.font] = boldFont
                return NSAttributedString(string: inner, attributes: boldAttrs)
            }),
            // Italic /text/
            ("(?<![\\w/])/([^/]+?)/(?![\\w/])", { match, attrs in
                var italAttrs = attrs
                let inner = String(match.dropFirst().dropLast())
                italAttrs[.font] = italicFont
                return NSAttributedString(string: inner, attributes: italAttrs)
            }),
            // Strikethrough +text+
            ("(?<![\\w+])\\+([^+]+?)\\+(?![\\w+])", { match, attrs in
                var strikeAttrs = attrs
                let inner = String(match.dropFirst().dropLast())
                strikeAttrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                return NSAttributedString(string: inner, attributes: strikeAttrs)
            }),
        ]

        while !remaining.isEmpty {
            // Find the earliest match across all patterns
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
                // No more matches
                result.append(NSAttributedString(string: remaining, attributes: currentAttrs))
                break
            }

            // Append text before match
            let before = String(remaining[..<matchRange.lowerBound])
            if !before.isEmpty {
                result.append(NSAttributedString(string: before, attributes: currentAttrs))
            }

            // Process match
            let matchText = String(remaining[matchRange])
            let formatted = patterns[patIdx].handler(matchText, currentAttrs)
            result.append(formatted)

            remaining = String(remaining[matchRange.upperBound...])
        }

        return result
    }

    private func monoFontForSize(_ attrs: [NSAttributedString.Key: Any]) -> NSFont {
        let size = (attrs[.font] as? NSFont)?.pointSize ?? 12
        return NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular)
    }
}

#Preview {
    OrgPreviewView(content: """
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
