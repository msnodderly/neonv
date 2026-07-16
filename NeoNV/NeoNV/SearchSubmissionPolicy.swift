import Foundation

enum SearchSubmissionPolicy {
    struct NoteIdentity {
        let id: UUID
        let title: String
        let relativePath: String
    }

    enum Action: Equatable {
        case create(String)
        case focusEditor
        case navigateToResults
        case none
        case open(UUID)
    }

    static func resolve(
        query: String,
        notes: [NoteIdentity],
        emptyQueryMatchCount: Int,
        defaultExtension: String = "md"
    ) -> Action {
        if query.isEmpty {
            if emptyQueryMatchCount == 1 {
                return .focusEditor
            }
            if emptyQueryMatchCount > 1 {
                return .navigateToResults
            }
            return .none
        }

        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .none
        }

        let normalizedTitleQuery = normalizeTitle(query)
        let normalizedPathQuery = normalizePath(query)
        let destination = NotePathNaming.relativePath(
            for: query,
            defaultExtension: defaultExtension
        )
        let normalizedDestination = destination.map(normalizePath)

        if let exactMatch = notes.first(where: { note in
            if !normalizedTitleQuery.isEmpty,
               normalizeTitle(note.title) == normalizedTitleQuery {
                return true
            }

            let notePath = normalizePath(note.relativePath)
            return pathAliases(for: notePath).contains(normalizedPathQuery)
                || notePath == normalizedDestination
        }) {
            return .open(exactMatch.id)
        }

        // A query whose components are all "."/".." (e.g. ".", "/", "..") has no
        // creatable destination; without this guard resolve would return .create
        // and the hint would promise creation that createNewNote(from:) silently drops.
        guard destination != nil else { return .none }
        return .create(query)
    }

    static func hint(for action: Action, matchCount: Int) -> String? {
        switch action {
        case .create:
            guard matchCount > 0 else { return "⏎ to create" }
            let noun = matchCount == 1 ? "match" : "matches"
            return "\(matchCount) \(noun) · ⏎ to create"
        case .open:
            return "Exact match · ⏎ to open"
        case .focusEditor, .navigateToResults, .none:
            return nil
        }
    }

    private static func normalizeTitle(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.hasPrefix("#") {
            normalized = normalized.drop(while: { $0 == "#" || $0 == " " }).description
        }
        if normalized.hasPrefix("- ") || normalized.hasPrefix("* ") || normalized.hasPrefix("+ ") {
            normalized = String(normalized.dropFirst(2))
        }
        if normalized.hasPrefix("> ") {
            normalized = String(normalized.dropFirst(2))
        }

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizePath(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .filter { $0 != "." && $0 != ".." }
            .joined(separator: "/")
            .lowercased()
    }

    private static func pathAliases(for relativePath: String) -> Set<String> {
        let path = normalizePath(relativePath)
        let pathWithoutExtension = removingRecognizedExtension(from: path)
        let filename = path.split(separator: "/").last.map(String.init) ?? path
        let basename = removingRecognizedExtension(from: filename)

        return [path, pathWithoutExtension, filename, basename]
    }

    private static func removingRecognizedExtension(from path: String) -> String {
        NotePathNaming.splitRecognizedExtension(from: path).base
    }
}

enum NotePathNaming {
    /// The note file extensions NeoNV recognizes — the single source of truth
    /// for discovery, file watching, renaming, and wiki-link normalization.
    static let validExtensions = ["md", "txt", "org", "markdown", "text"]
    static let validExtensionSet = Set(validExtensions)

    static func relativePath(for input: String, defaultExtension: String) -> String? {
        var components = pathComponents(for: input)
        guard !components.isEmpty else { return nil }

        if let last = components.last, !hasValidExtension(last) {
            components[components.count - 1] = "\(last).\(defaultExtension)"
        }

        return components.joined(separator: "/")
    }

    static func pathComponents(for input: String) -> [String] {
        let normalized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        let rawParts = normalized
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        return rawParts.enumerated().compactMap { index, part in
            guard part != "." && part != ".." else { return nil }
            return sanitizePathComponent(
                part,
                preserveExtension: index == rawParts.count - 1
            )
        }
    }

    static func hasValidExtension(_ name: String) -> Bool {
        splitRecognizedExtension(from: name).ext != nil
    }

    /// Splits a recognized note extension off the end of `name`, returning the
    /// base (original case preserved, without the extension) and the matched
    /// lowercased extension. Returns `(name, nil)` when no recognized extension
    /// is present. The single source of truth for extension detection.
    static func splitRecognizedExtension(from name: String) -> (base: String, ext: String?) {
        let lowercased = name.lowercased()
        for ext in validExtensions where lowercased.hasSuffix(".\(ext)") {
            return (String(name.dropLast(ext.count + 1)), ext)
        }
        return (name, nil)
    }

    private static func sanitizePathComponent(
        _ name: String,
        preserveExtension: Bool
    ) -> String {
        var baseName = name
        var extensionPart: String?

        if preserveExtension {
            let split = splitRecognizedExtension(from: name)
            baseName = split.base
            extensionPart = split.ext
        }

        var sanitized = baseName.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)

        if sanitized.count > 100 {
            sanitized = String(sanitized.prefix(100))
        }
        if sanitized.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            sanitized = "untitled-\(formatter.string(from: Date()))"
        }
        if let extensionPart {
            sanitized += ".\(extensionPart)"
        }

        return sanitized
    }
}
