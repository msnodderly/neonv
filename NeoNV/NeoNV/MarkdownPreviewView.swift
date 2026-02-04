import SwiftUI
import AppKit

struct MarkdownPreviewView: NSViewRepresentable {
    var content: String
    var fontSize: CGFloat = 13
    var onShiftTab: (() -> Void)?
    var onTypeToEdit: ((String?) -> Void)?

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
        let attributedString = parseMarkdown(content: content, fontSize: fontSize)
        textView.textStorage?.setAttributedString(attributedString)
    }

    private struct HeaderStyle {
        let prefix: String
        let sizeOffset: CGFloat
        let weight: NSFont.Weight
    }

    private static let headerStyles: [HeaderStyle] = [
        HeaderStyle(prefix: "######", sizeOffset: 1, weight: .semibold),
        HeaderStyle(prefix: "#####", sizeOffset: 2, weight: .semibold),
        HeaderStyle(prefix: "####", sizeOffset: 3, weight: .semibold),
        HeaderStyle(prefix: "###", sizeOffset: 4, weight: .semibold),
        HeaderStyle(prefix: "##", sizeOffset: 6, weight: .bold),
        HeaderStyle(prefix: "#", sizeOffset: 10, weight: .bold)
    ]

    private func parseHeader(line: String, fontSize: CGFloat) -> (text: String, font: NSFont)? {
        for style in Self.headerStyles where line.hasPrefix(style.prefix) {
            let text = String(line.dropFirst(style.prefix.count)).trimmingCharacters(in: .whitespaces)
            let font = NSFont.systemFont(ofSize: fontSize + style.sizeOffset, weight: style.weight)
            return (text, font)
        }
        return nil
    }

    private enum TableAlignment {
        case left, center, right
    }

    private struct ParsedTable {
        var headers: [String]
        var alignments: [TableAlignment]
        var rows: [[String]]
    }

    private func isTableSeparatorLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") else { return false }
        let cells = parseCells(from: trimmed)
        return !cells.isEmpty && cells.allSatisfy { cell in
            let c = cell.trimmingCharacters(in: .whitespaces)
            return c.allSatisfy { $0 == "-" || $0 == ":" } && c.contains("-")
        }
    }

    private func parseAlignments(from line: String) -> [TableAlignment] {
        parseCells(from: line).map { cell in
            let c = cell.trimmingCharacters(in: .whitespaces)
            let left = c.hasPrefix(":")
            let right = c.hasSuffix(":")
            if left && right { return .center }
            if right { return .right }
            return .left
        }
    }

    private func parseCells(from line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var content = trimmed
        if content.hasPrefix("|") { content = String(content.dropFirst()) }
        if content.hasSuffix("|") { content = String(content.dropLast()) }
        return content.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    private func isTableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.contains("|") &&
               trimmed.filter({ $0 == "|" }).count >= 2
    }

    private func parseTableBlock(_ tableLines: [String]) -> ParsedTable? {
        guard tableLines.count >= 2 else { return nil }

        // Check if line 1 is separator (header | separator | rows)
        guard tableLines.count >= 2, isTableSeparatorLine(tableLines[1]) else { return nil }

        let headers = parseCells(from: tableLines[0])
        let alignments = parseAlignments(from: tableLines[1])
        var rows: [[String]] = []

        for i in 2..<tableLines.count {
            let cells = parseCells(from: tableLines[i])
            rows.append(cells)
        }

        return ParsedTable(headers: headers, alignments: alignments, rows: rows)
    }

    private func renderTable(
        _ table: ParsedTable,
        fontSize: CGFloat,
        baseFont: NSFont,
        boldFont: NSFont,
        italicFont: NSFont,
        monoFont: NSFont,
        codeBackground: NSColor
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let textColor = NSColor.textColor
        let headerBg = NSColor.controlAccentColor.withAlphaComponent(0.08)
        let borderColor = NSColor.separatorColor
        let colCount = max(table.headers.count, table.rows.map(\.count).max() ?? 1)

        let nsTable = NSTextTable()
        nsTable.numberOfColumns = colCount
        nsTable.setContentWidth(100, type: .percentageValueType)
        nsTable.hidesEmptyCells = false

        func makeCell(
            text: String, row: Int, col: Int, isHeader: Bool,
            alignment: TableAlignment
        ) -> NSAttributedString {
            let block = NSTextTableBlock(
                table: nsTable,
                startingRow: row, rowSpan: 1,
                startingColumn: col, columnSpan: 1
            )

            for edge: NSRectEdge in [.minX, .minY, .maxX, .maxY] {
                block.setBorderColor(borderColor, for: edge)
                block.setWidth(0.5, type: .absoluteValueType, for: .border, edge: edge)
                let padAmount: CGFloat = (edge == .minX || edge == .maxX) ? 6 : 3
                block.setWidth(padAmount, type: .absoluteValueType, for: .padding, edge: edge)
            }

            block.setContentWidth(CGFloat(100 / colCount), type: .percentageValueType)

            if isHeader {
                block.backgroundColor = headerBg
            }

            let para = NSMutableParagraphStyle()
            para.textBlocks = [block]
            switch alignment {
            case .left: para.alignment = .left
            case .center: para.alignment = .center
            case .right: para.alignment = .right
            }

            let font = isHeader ? boldFont : baseFont
            let baseAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: para
            ]

            // Process inline formatting within cell
            let formatted = processInlineFormatting(
                text,
                baseAttrs: baseAttrs,
                boldFont: boldFont,
                italicFont: italicFont,
                monoFont: monoFont,
                codeBackground: codeBackground
            )

            // Ensure paragraph style is applied to entire string
            let cellStr = NSMutableAttributedString(attributedString: formatted)
            cellStr.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: cellStr.length))
            cellStr.append(NSAttributedString(string: "\n", attributes: baseAttrs))
            return cellStr
        }

        // Render header row
        for col in 0..<colCount {
            let text = col < table.headers.count ? table.headers[col] : ""
            let alignment = col < table.alignments.count ? table.alignments[col] : .left
            result.append(makeCell(text: text, row: 0, col: col, isHeader: true, alignment: alignment))
        }

        // Render data rows
        for (rowIdx, row) in table.rows.enumerated() {
            for col in 0..<colCount {
                let text = col < row.count ? row[col] : ""
                let alignment = col < table.alignments.count ? table.alignments[col] : .left
                result.append(makeCell(text: text, row: rowIdx + 1, col: col, isHeader: false, alignment: alignment))
            }
        }

        return result
    }

    private func parseMarkdown(content: String, fontSize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = content.components(separatedBy: "\n")

        let baseFont = NSFont.systemFont(ofSize: fontSize)
        let monoFont = NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)
        let boldFont = NSFont.boldSystemFont(ofSize: fontSize)
        let italicFont = NSFont.systemFont(ofSize: fontSize).withTraits(.italicFontMask)
        let textColor = NSColor.textColor
        let secondaryColor = NSColor.secondaryLabelColor
        let codeBackground = NSColor.quaternaryLabelColor

        var inCodeBlock = false
        var codeBlockContent = ""
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if line.hasPrefix("```") {
                if inCodeBlock {
                    let codeAttrs: [NSAttributedString.Key: Any] = [
                        .font: monoFont,
                        .foregroundColor: textColor,
                        .backgroundColor: codeBackground
                    ]
                    result.append(NSAttributedString(string: codeBlockContent, attributes: codeAttrs))
                    codeBlockContent = ""
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
                index += 1
                continue
            }

            if inCodeBlock {
                codeBlockContent += line + "\n"
                index += 1
                continue
            }

            // Detect table blocks
            if isTableLine(line) {
                var tableLines: [String] = []
                var tableEnd = index
                while tableEnd < lines.count && isTableLine(lines[tableEnd]) {
                    tableLines.append(lines[tableEnd])
                    tableEnd += 1
                }

                if let table = parseTableBlock(tableLines) {
                    let tableStr = renderTable(
                        table, fontSize: fontSize,
                        baseFont: baseFont, boldFont: boldFont,
                        italicFont: italicFont, monoFont: monoFont,
                        codeBackground: codeBackground
                    )
                    result.append(tableStr)
                    index = tableEnd
                    continue
                }
            }

            var processedLine = line
            var attrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: textColor
            ]

            if let header = parseHeader(line: line, fontSize: fontSize) {
                processedLine = header.text
                attrs[.font] = header.font
            } else if line.hasPrefix(">") {
                processedLine = "  │ " + String(line.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                attrs[.foregroundColor] = secondaryColor
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                processedLine = "  • " + String(line.dropFirst(2))
            } else if line == "---" || line == "***" || line == "___" {
                processedLine = "────────────────────────────────────────"
                attrs[.foregroundColor] = secondaryColor
            }

            // Check for @done tag or completed checkbox — apply strikethrough and dim
            let isDone = processedLine.contains("@done") || line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ")
            if isDone {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attrs[.strikethroughColor] = secondaryColor
                attrs[.foregroundColor] = secondaryColor
            }

            // Process inline formatting
            let attributedLine = processInlineFormatting(
                processedLine,
                baseAttrs: attrs,
                boldFont: boldFont,
                italicFont: italicFont,
                monoFont: monoFont,
                codeBackground: codeBackground
            )

            result.append(attributedLine)

            // Add newline between lines
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: attrs))
            }

            index += 1
        }

        // Handle unclosed code block
        if inCodeBlock && !codeBlockContent.isEmpty {
            let codeAttrs: [NSAttributedString.Key: Any] = [
                .font: monoFont,
                .foregroundColor: textColor,
                .backgroundColor: codeBackground
            ]
            result.append(NSAttributedString(string: codeBlockContent, attributes: codeAttrs))
        }

        return result
    }

    private func processInlineFormatting(
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

        while !remaining.isEmpty {
            // Inline code
            if let codeRange = remaining.range(of: "`[^`]+`", options: .regularExpression) {
                // Add text before code
                let beforeCode = String(remaining[..<codeRange.lowerBound])
                if !beforeCode.isEmpty {
                    result.append(NSAttributedString(string: beforeCode, attributes: currentAttrs))
                }

                // Add code
                var codeText = String(remaining[codeRange])
                codeText = String(codeText.dropFirst().dropLast()) // Remove backticks
                var codeAttrs = currentAttrs
                codeAttrs[.font] = monoFont
                codeAttrs[.backgroundColor] = codeBackground
                result.append(NSAttributedString(string: codeText, attributes: codeAttrs))

                remaining = String(remaining[codeRange.upperBound...])
                continue
            }

            // Bold (**text** or __text__)
            if let boldRange = remaining.range(of: "\\*\\*[^*]+\\*\\*|__[^_]+__", options: .regularExpression) {
                let beforeBold = String(remaining[..<boldRange.lowerBound])
                if !beforeBold.isEmpty {
                    result.append(NSAttributedString(string: beforeBold, attributes: currentAttrs))
                }

                var boldText = String(remaining[boldRange])
                boldText = String(boldText.dropFirst(2).dropLast(2))
                var boldAttrs = currentAttrs
                boldAttrs[.font] = boldFont
                result.append(NSAttributedString(string: boldText, attributes: boldAttrs))

                remaining = String(remaining[boldRange.upperBound...])
                continue
            }

            // Italic (*text* or _text_)
            if let italicRange = remaining.range(of: "(?<!\\*)\\*(?!\\*)[^*]+\\*(?!\\*)|(?<!_)_(?!_)[^_]+_(?!_)", options: .regularExpression) {
                let beforeItalic = String(remaining[..<italicRange.lowerBound])
                if !beforeItalic.isEmpty {
                    result.append(NSAttributedString(string: beforeItalic, attributes: currentAttrs))
                }

                var italicText = String(remaining[italicRange])
                italicText = String(italicText.dropFirst().dropLast())
                var italicAttrs = currentAttrs
                italicAttrs[.font] = italicFont
                result.append(NSAttributedString(string: italicText, attributes: italicAttrs))

                remaining = String(remaining[italicRange.upperBound...])
                continue
            }

            // Links [text](url)
            if let linkRange = remaining.range(of: "\\[[^\\]]+\\]\\([^)]+\\)", options: .regularExpression) {
                let beforeLink = String(remaining[..<linkRange.lowerBound])
                if !beforeLink.isEmpty {
                    result.append(NSAttributedString(string: beforeLink, attributes: currentAttrs))
                }

                let linkText = String(remaining[linkRange])
                if let textEnd = linkText.firstIndex(of: "]"),
                   let urlStart = linkText.firstIndex(of: "(") {
                    let displayText = String(linkText[linkText.index(after: linkText.startIndex)..<textEnd])
                    let urlText = String(linkText[linkText.index(after: urlStart)..<linkText.index(before: linkText.endIndex)])

                    var linkAttrs = currentAttrs
                    linkAttrs[.foregroundColor] = NSColor.linkColor
                    linkAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    if let url = URL(string: urlText) {
                        linkAttrs[.link] = url
                    }
                    result.append(NSAttributedString(string: displayText, attributes: linkAttrs))
                }

                remaining = String(remaining[linkRange.upperBound...])
                continue
            }

            // No more formatting found, append remaining text
            result.append(NSAttributedString(string: remaining, attributes: currentAttrs))
            break
        }

        return result
    }
}

extension NSFont {
    func withTraits(_ traits: NSFontTraitMask) -> NSFont {
        let fontManager = NSFontManager.shared
        return fontManager.font(
            withFamily: self.familyName ?? "System",
            traits: traits,
            weight: 5,
            size: self.pointSize
        ) ?? self
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

class PreviewTextView: NSTextView {
    var onShiftTab: (() -> Void)?
    var onTypeToEdit: ((String) -> Void)?

    override func keyDown(with event: NSEvent) {
        // Shift-Tab to return to note list
        if event.keyCode == 48 && event.modifierFlags.contains(.shift) {
            onShiftTab?()
            return
        }

        // Escape to note list
        if event.keyCode == 53 {
            onShiftTab?()
            return
        }

        // Page Up/Down for scrolling
        if event.keyCode == 116 { // Page Up
            pageUp(nil)
            return
        }
        if event.keyCode == 121 { // Page Down
            pageDown(nil)
            return
        }

        // Up/Down arrow for scrolling
        if event.keyCode == 126 { // Up arrow
            scrollUp()
            return
        }
        if event.keyCode == 125 { // Down arrow
            scrollDown()
            return
        }

        // Type-to-exit: any letter, number, or character key switches to editor
        if let chars = event.characters,
           !chars.isEmpty,
           !event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.control) {
            // Check if it's a printable character (letter, number, punctuation, or space)
            let firstChar = chars.unicodeScalars.first!
            if CharacterSet.alphanumerics.contains(firstChar) ||
               CharacterSet.punctuationCharacters.contains(firstChar) ||
               CharacterSet.symbols.contains(firstChar) ||
               chars == " " || chars == "\t" {
                onTypeToEdit?(chars)
                return
            }
        }

        super.keyDown(with: event)
    }

    func scrollUp(_ lineCount: Int = 1) {
        guard let scrollView = enclosingScrollView else { return }
        let clipView = scrollView.contentView
        var newOrigin = clipView.bounds.origin
        newOrigin.y = max(0, newOrigin.y - CGFloat(lineCount * 20))
        clipView.scroll(to: newOrigin)
        scrollView.reflectScrolledClipView(clipView)
    }

    func scrollDown(_ lineCount: Int = 1) {
        guard let scrollView = enclosingScrollView else { return }
        let clipView = scrollView.contentView
        let documentHeight = bounds.height
        let visibleHeight = scrollView.contentView.bounds.height
        var newOrigin = clipView.bounds.origin
        newOrigin.y = min(documentHeight - visibleHeight, newOrigin.y + CGFloat(lineCount * 20))
        if newOrigin.y < 0 { newOrigin.y = 0 }
        clipView.scroll(to: newOrigin)
        scrollView.reflectScrolledClipView(clipView)
    }
}

#Preview {
    MarkdownPreviewView(content: """
    # Header 1
    ## Header 2
    ### Header 3

    This is **bold** and this is *italic*.

    - List item 1
    - List item 2
    - List item 3

    > This is a blockquote

    `inline code` and more text.

    ```
    code block
    multiple lines
    ```

    [Link text](https://example.com)

    ---

    | Feature | Status | Notes |
    |---------|:------:|------:|
    | Tables | **Done** | Right-aligned |
    | Lists | Done | |
    | Code | Done | `inline` too |

    Regular paragraph text continues here.
    """)
    .frame(width: 400, height: 500)
}
