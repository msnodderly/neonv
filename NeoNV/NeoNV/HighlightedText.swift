import SwiftUI
import AppKit

struct HighlightedText: View {
    let text: String
    let searchTerms: [String]
    let highlightColor: Color
    let baseFont: Font
    let baseColor: Color

    init(
        _ text: String,
        highlighting searchTerms: [String],
        highlightColor: Color = Color.yellow.opacity(0.4),
        font: Font = .body,
        color: Color = .primary
    ) {
        self.text = text
        self.searchTerms = searchTerms.filter { !$0.isEmpty }
        self.highlightColor = highlightColor
        self.baseFont = font
        self.baseColor = color
    }

    var body: some View {
        Text(buildAttributedString())
            .font(baseFont)
            .foregroundColor(baseColor)
    }

    private func buildAttributedString() -> AttributedString {
        var attributedString = AttributedString(text)
        
        guard !searchTerms.isEmpty else {
            return attributedString
        }

        let ranges = findAllRanges()
        let highlightUIColor = NSColor(highlightColor)

        for range in ranges {
            let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
            let endOffset = text.distance(from: text.startIndex, to: range.upperBound)
            
            let attrStart = attributedString.index(attributedString.startIndex, offsetByCharacters: startOffset)
            let attrEnd = attributedString.index(attributedString.startIndex, offsetByCharacters: endOffset)
            attributedString[attrStart..<attrEnd].backgroundColor = highlightUIColor
        }

        return attributedString
    }

    private func findAllRanges() -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        let lowercasedText = text.lowercased()

        for term in searchTerms {
            let lowercasedTerm = term.lowercased()
            var searchStart = lowercasedText.startIndex

            while searchStart < lowercasedText.endIndex {
                if let range = lowercasedText.range(of: lowercasedTerm, range: searchStart..<lowercasedText.endIndex) {
                    let originalRange = Range(uncheckedBounds: (
                        lower: text.index(text.startIndex, offsetBy: lowercasedText.distance(from: lowercasedText.startIndex, to: range.lowerBound)),
                        upper: text.index(text.startIndex, offsetBy: lowercasedText.distance(from: lowercasedText.startIndex, to: range.upperBound))
                    ))
                    ranges.append(originalRange)
                    searchStart = range.upperBound
                } else {
                    break
                }
            }
        }

        return mergeOverlappingRanges(ranges.sorted { $0.lowerBound < $1.lowerBound })
    }

    private func mergeOverlappingRanges(_ sortedRanges: [Range<String.Index>]) -> [Range<String.Index>] {
        guard !sortedRanges.isEmpty else { return [] }

        var merged: [Range<String.Index>] = []
        var current = sortedRanges[0]

        for range in sortedRanges.dropFirst() {
            if range.lowerBound <= current.upperBound {
                current = current.lowerBound..<max(current.upperBound, range.upperBound)
            } else {
                merged.append(current)
                current = range
            }
        }
        merged.append(current)

        return merged
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        HighlightedText(
            "Meeting with design team",
            highlighting: ["design"],
            font: .system(size: 13, weight: .medium),
            color: .primary
        )

        HighlightedText(
            "work/meeting-notes.md",
            highlighting: ["meet"],
            font: .system(size: 11),
            color: .secondary
        )

        HighlightedText(
            "No matches here",
            highlighting: ["xyz"],
            font: .body,
            color: .primary
        )

        HighlightedText(
            "Multiple matches: test test test",
            highlighting: ["test"],
            font: .body,
            color: .primary
        )
    }
    .padding()
}
