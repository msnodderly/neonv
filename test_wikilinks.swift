import Foundation

// Test wiki-link parsing function
func testWikiLinkParsing() {
    let testText = """
    This is a note with [[wiki links]].
    Here's an [[incomplete link]] and another [[complete link]].
    A link to a non-existent page: [[Non-existent Note]]
    """
    
    print("Testing wiki-link parsing...")
    print("Input text:")
    print(testText)
    print("\n---\n")
    
    // This would be implemented in the actual app
    // For now, let's just verify the regex logic
    let nsText = testText as NSString
    
    var searchStart = 0
    var foundLinks: [(NSRange, String)] = []
    
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
        
        foundLinks.append((linkRange, title))
        print("Found wiki link: '\(title)' at range \(linkRange), complete: \(isComplete)")
        
        searchStart = isComplete ? endRange.location + 2 : openBracketRange.location + 2
    }
    
    print("\n--- Summary ---")
    print("Found \(foundLinks.count) wiki links:")
    for (index, (_, title)) in foundLinks.enumerated() {
        print("\(index + 1). \(title)")
    }
}

testWikiLinkParsing()