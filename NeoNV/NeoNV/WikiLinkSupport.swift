import Foundation

enum WikiLinkResolution {
    case resolved(NoteFile)
    case missing(String)
    case ambiguous([NoteFile])
}

struct WikiLinkSuggestion: Identifiable, Hashable {
    let insertTarget: String
    let display: String
    let detailPath: String

    var id: String { "\(insertTarget)|\(detailPath)" }
}

struct WikiLinkMatch: Equatable {
    let fullRange: NSRange
    let target: String
    let label: String?

    var displayText: String {
        if let label, !label.isEmpty {
            return label
        }
        return target
    }
}

struct WikiLinkContext {
    let query: String
    let replacementRange: NSRange
    let hasClosingBrackets: Bool
}

enum WikiLinkURLCodec {
    static let scheme = "neonv-wiki"

    static func url(forTarget target: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "target", value: target)]
        return components.url
    }

    static func target(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "target" })?.value
    }
}

enum WikiLinkParser {
    // [[target]] or [[target|label]]
    private static let regex = try? NSRegularExpression(pattern: #"\[\[([^\]|]+?)(?:\|([^\]]+?))?\]\]"#)

    static func matches(in text: String) -> [WikiLinkMatch] {
        guard let regex else { return [] }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let results = regex.matches(in: text, options: [], range: fullRange)

        return results.compactMap { result in
            guard result.numberOfRanges >= 2 else { return nil }
            let targetRange = result.range(at: 1)
            guard targetRange.location != NSNotFound else { return nil }

            let target = nsText.substring(with: targetRange).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty else { return nil }

            var label: String?
            if result.numberOfRanges > 2 {
                let labelRange = result.range(at: 2)
                if labelRange.location != NSNotFound {
                    let parsed = nsText.substring(with: labelRange).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !parsed.isEmpty {
                        label = parsed
                    }
                }
            }

            return WikiLinkMatch(fullRange: result.range, target: target, label: label)
        }
    }

    static func parseTargetAndLabel(from innerContent: String) -> (target: String, label: String?) {
        if let pipeIndex = innerContent.firstIndex(of: "|") {
            let target = String(innerContent[..<pipeIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let label = String(innerContent[innerContent.index(after: pipeIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (target, label.isEmpty ? nil : label)
        }
        let target = innerContent.trimmingCharacters(in: .whitespacesAndNewlines)
        return (target, nil)
    }

    static func contextAtCursor(in text: NSString, cursorLocation: Int) -> WikiLinkContext? {
        let safeCursor = max(0, min(cursorLocation, text.length))
        let searchRange = NSRange(location: 0, length: safeCursor)

        let openRange = text.range(of: "[[", options: .backwards, range: searchRange)
        guard openRange.location != NSNotFound else { return nil }

        let contentStart = openRange.location + openRange.length
        guard contentStart <= safeCursor else { return nil }

        // If a closing marker exists before the cursor, the cursor isn't inside this wiki target.
        if safeCursor > contentStart {
            let preCursorRange = NSRange(location: contentStart, length: safeCursor - contentStart)
            let closedBeforeCursor = text.range(of: "]]", options: [], range: preCursorRange)
            if closedBeforeCursor.location != NSNotFound {
                return nil
            }
            // Wiki-link targets are single-line. If cursor moved to a later line,
            // do not treat this as an active completion context.
            let newlineBeforeCursor = text.range(of: "\n", options: [], range: preCursorRange)
            if newlineBeforeCursor.location != NSNotFound {
                return nil
            }
        }

        let fromContentToEnd = NSRange(location: contentStart, length: text.length - contentStart)
        let closeRange = text.range(of: "]]", options: [], range: fromContentToEnd)
        let hasClosingBrackets = closeRange.location != NSNotFound
        // For unclosed wiki links, never let replacement extend beyond the cursor.
        // Otherwise completion can overwrite the remainder of the document.
        let closeLocation = hasClosingBrackets ? closeRange.location : safeCursor

        let beforeCloseRange = NSRange(location: contentStart, length: max(0, closeLocation - contentStart))
        let pipeRange = text.range(of: "|", options: [], range: beforeCloseRange)
        let targetEnd = pipeRange.location == NSNotFound ? closeLocation : pipeRange.location

        guard safeCursor >= contentStart, safeCursor <= targetEnd else { return nil }

        let replacementRange = NSRange(location: contentStart, length: max(0, targetEnd - contentStart))
        let queryRange = NSRange(location: contentStart, length: max(0, safeCursor - contentStart))
        let query = queryRange.length > 0 ? text.substring(with: queryRange) : ""

        return WikiLinkContext(
            query: query,
            replacementRange: replacementRange,
            hasClosingBrackets: hasClosingBrackets
        )
    }
}

func isLikelyExternalURL(_ raw: String) -> Bool {
    guard let url = URL(string: raw), let scheme = url.scheme?.lowercased() else {
        return false
    }
    return ["http", "https", "mailto"].contains(scheme)
}
