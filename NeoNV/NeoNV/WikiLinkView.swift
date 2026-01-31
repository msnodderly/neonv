import SwiftUI
import AppKit

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

struct WikiLinkAutocomplete: View {
    let links: [WikiLink]
    let allNotes: [NoteFile]
    let onSelectNote: (NoteFile) -> Void
    let onCreateNote: (String) -> Void
    
    private var currentIncompleteLink: WikiLink? {
        links.first { !$0.isComplete && $0.range.location >= 0 }
    }
    
    private var suggestions: [NoteFile] {
        guard let incomplete = currentIncompleteLink, !incomplete.title.isEmpty else { return [] }
        
        let searchTerm = incomplete.title.lowercased()
        return allNotes.filter { note in
            note.displayTitle.lowercased().contains(searchTerm) ||
            note.title.lowercased().contains(searchTerm)
        }.sorted { note1, note2 in
            // Prefer exact matches, then prefix matches, then alphabetical
            let term1 = note1.displayTitle.lowercased()
            let term2 = note2.displayTitle.lowercased()
            
            if term1 == searchTerm && term2 != searchTerm { return true }
            if term2 == searchTerm && term1 != searchTerm { return false }
            if term1.hasPrefix(searchTerm) && !term2.hasPrefix(searchTerm) { return true }
            if !term1.hasPrefix(searchTerm) && term2.hasPrefix(searchTerm) { return false }
            
            return term1 < term2
        }.prefix(5).map { $0 }
    }
    
    var body: some View {
        if let incomplete = currentIncompleteLink, !incomplete.title.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if suggestions.isEmpty {
                    Button(action: { onCreateNote(incomplete.title) }) {
                        HStack {
                            Image(systemName: "plus")
                                .foregroundColor(.secondary)
                            Text("Create \"\(incomplete.title)\"")
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Color(NSColor.controlBackgroundColor))
                    .onHover { isHovering in
                        if isHovering {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                } else {
                    ForEach(suggestions, id: \.id) { note in
                        Button(action: { onSelectNote(note) }) {
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundColor(.secondary)
                                Text(note.displayTitle)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(note.displayPath)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color(NSColor.controlBackgroundColor))
                        .onHover { isHovering in
                            if isHovering {
                                NSCursor.pointingHand.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                        }
                    }
                }
            }
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
            .cornerRadius(6)
            .shadow(radius: 4)
        } else {
            EmptyView()
        }
    }
}

struct WikiLinkHighlightedText: View {
    let text: String
    let wikiLinks: [WikiLink]
    let font: Font
    let color: Color
    let onLinkClick: (WikiLink) -> Void
    
    init(
        _ text: String,
        wikiLinks: [WikiLink],
        font: Font = .body,
        color: Color = .primary,
        onLinkClick: @escaping (WikiLink) -> Void
    ) {
        self.text = text
        self.wikiLinks = wikiLinks
        self.font = font
        self.color = color
        self.onLinkClick = onLinkClick
    }
    
    var body: some View {
        Text(buildAttributedString())
            .font(font)
            .foregroundColor(color)
            .textSelection(.enabled)
    }
    
    private func buildAttributedString() -> AttributedString {
        var attributedString = AttributedString(text)
        
        for link in wikiLinks.sorted(by: { $0.range.location < $1.range.location }) {
            let startOffset = text.distance(from: text.startIndex, to: text.index(text.startIndex, offsetBy: link.range.location))
            let endOffset = startOffset + link.range.length
            
            guard startOffset < attributedString.characters.count,
                  endOffset <= attributedString.characters.count else { continue }
            
            let attrStart = attributedString.index(attributedString.startIndex, offsetByCharacters: startOffset)
            let attrEnd = attributedString.index(attributedString.startIndex, offsetByCharacters: endOffset)
            
            // Style the link
            attributedString[attrStart..<attrEnd].foregroundColor = link.matchedNote != nil ? .blue : .orange
            attributedString[attrStart..<attrEnd].underlineStyle = .single
            
            if !link.isComplete {
                attributedString[attrStart..<attrEnd].backgroundColor = .orange.opacity(0.2)
            }
        }
        
        return attributedString
    }
}