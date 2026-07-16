import Foundation
import AppKit
import CoreServices
import CryptoKit
import os

/// Thread-safe cancellation flag for bridging structured concurrency to GCD
private final class CancellationFlag: @unchecked Sendable {
    private let _cancelled = OSAllocatedUnfairLock(initialState: false)
    var isCancelled: Bool {
        get { _cancelled.withLock { $0 } }
        set { _cancelled.withLock { $0 = newValue } }
    }
}

struct NoteFile: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let relativePath: String
    var modificationDate: Date
    var title: String
    var contentPreview: String
    /// Original-case file content, capped at `NoteStore.searchIndexMaxBytes`.
    /// Powers full-content search (via its lowercased copy in `searchCombined`)
    /// and deep-match snippets. Empty for unsaved notes and cache-warmed notes
    /// until discovery refreshes them; never persisted to the metadata cache.
    private(set) var indexedContent: String = ""
    var isUnsaved: Bool = false
    var isReadOnly: Bool = false
    var tags: [String] = []

    /// Pre-computed lowercased strings for fast search matching
    private(set) var searchTitle: String = ""
    private(set) var searchPath: String = ""
    private(set) var searchPreview: String = ""
    private(set) var searchTags: String = ""

    // swiftlint:disable:next line_length
    init(id: UUID? = nil, url: URL, relativePath: String, modificationDate: Date, title: String, contentPreview: String = "", indexedContent: String = "", isUnsaved: Bool = false, isReadOnly: Bool = false, tags: [String] = []) {
        self.id = id ?? Self.stableID(for: url)
        self.url = url
        self.relativePath = relativePath
        self.modificationDate = modificationDate
        self.title = title
        self.contentPreview = contentPreview
        self.indexedContent = indexedContent
        self.isUnsaved = isUnsaved
        self.isReadOnly = isReadOnly
        self.tags = tags
        self.searchTitle = title.lowercased()
        self.searchPath = relativePath.lowercased()
        self.searchPreview = contentPreview.lowercased()
        self.searchTags = tags.joined(separator: " ").lowercased()
        self.searchCombined = Self.combine(title: searchTitle, path: searchPath,
                                           preview: searchPreview, content: indexedContent, tags: searchTags)
    }

    /// Perf-sensitive: combine all searchable fields once so filtering can
    /// tokenize the query once per rebuild and do contains checks per term.
    private(set) var searchCombined: String = ""

    private static func combine(title: String, path: String, preview: String, content: String, tags: String) -> String {
        // Full content supersedes the preview when available (cache-warmed
        // notes only carry the preview until discovery refreshes them).
        let body = content.isEmpty ? preview : content.lowercased()
        return "\(title)\n\(path)\n\(body)\n\(tags)"
    }

    /// Splits a query into lowercased whitespace-separated search terms.
    static func searchTerms(from query: String) -> [String] {
        query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// AND-of-terms matching: every term must appear somewhere in the note's
    /// searchable text (title, path, content, tags). An empty term list
    /// matches everything, preserving empty-query behavior.
    func matches(allLowercasedTerms terms: [String]) -> Bool {
        terms.allSatisfy { searchCombined.contains($0) }
    }

    private static func stableID(for url: URL) -> UUID {
        let path = url.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80

        let uuidString = String(
            format: "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            bytes[6], bytes[7],
            bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuidString: uuidString) ?? UUID()
    }

    mutating func updateContent(title: String, contentPreview: String, indexedContent: String, modificationDate: Date, tags: [String] = []) {
        self.title = title
        self.contentPreview = contentPreview
        self.indexedContent = indexedContent
        self.modificationDate = modificationDate
        self.tags = tags
        self.isUnsaved = false
        self.searchTitle = title.lowercased()
        self.searchPreview = contentPreview.lowercased()
        self.searchTags = tags.joined(separator: " ").lowercased()
        self.searchCombined = Self.combine(title: searchTitle, path: searchPath,
                                           preview: searchPreview, content: indexedContent, tags: searchTags)
    }
    
    var displayTitle: String {
        var title = self.title
        
        if title.hasPrefix("#") {
            title = title.drop(while: { $0 == "#" || $0 == " " }).description
        }
        if title.hasPrefix("- ") || title.hasPrefix("* ") || title.hasPrefix("+ ") {
            title = String(title.dropFirst(2))
        }
        if title.hasPrefix("> ") {
            title = String(title.dropFirst(2))
        }
        
        if title.count > 50 {
            title = String(title.prefix(47)) + "..."
        }
        
        return title.isEmpty ? "Untitled" : title
    }
    
    var displayPath: String {
        if isUnsaved {
            return "[unsaved]"
        } else {
            return relativePath
        }
    }

    /// Preview text for list rows. When a search term matches the note body
    /// but the match sits past the visible head of the preview, the text is
    /// recentered on the earliest match (with a little lead-in context) so the
    /// row shows *why* the note is in the search results. Falls back to the
    /// full indexed content for matches past the preview head.
    func previewSnippet(matching terms: [String]) -> String {
        let flattenedPreview = contentPreview.replacingOccurrences(of: "\n", with: " ")
        guard !terms.isEmpty else { return flattenedPreview }

        // Common case first: the preview head is small and usually contains
        // the match, so the (potentially large) indexed content is only
        // flattened and searched for genuinely deep matches.
        if let matchRange = Self.earliestRange(of: terms, in: flattenedPreview) {
            return Self.recentered(flattenedPreview, around: matchRange)
        }
        if !indexedContent.isEmpty {
            let flattenedFull = indexedContent.replacingOccurrences(of: "\n", with: " ")
            if let matchRange = Self.earliestRange(of: terms, in: flattenedFull) {
                return Self.recentered(flattenedFull, around: matchRange)
            }
        }
        return flattenedPreview
    }

    private static func earliestRange(of terms: [String], in text: String) -> Range<String.Index>? {
        var earliest: Range<String.Index>?
        for term in terms {
            guard let range = text.range(of: term, options: .caseInsensitive) else { continue }
            if earliest == nil || range.lowerBound < earliest!.lowerBound {
                earliest = range
            }
        }
        return earliest
    }

    private static func recentered(_ text: String, around matchRange: Range<String.Index>) -> String {
        // A match near the head is already visible without recentering.
        let matchOffset = text.distance(from: text.startIndex, to: matchRange.lowerBound)
        guard matchOffset > 48 else { return String(text.prefix(300)) }

        // Back up a little context, then snap forward to a word boundary so
        // the snippet doesn't open mid-word.
        var snippetStart = text.index(matchRange.lowerBound, offsetBy: -24, limitedBy: text.startIndex)
            ?? text.startIndex
        if let space = text[snippetStart..<matchRange.lowerBound].firstIndex(of: " ") {
            snippetStart = text.index(after: space)
        }

        return "…" + String(text[snippetStart...].prefix(300))
    }
}

struct ExternalChangeEvent: Equatable {
    let id = UUID()
    let url: URL
    enum Kind {
        case modified
        case deleted
    }
    let kind: Kind

    static func == (lhs: ExternalChangeEvent, rhs: ExternalChangeEvent) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
class NoteStore: ObservableObject, FileWatcherDelegate {
    @Published var notes: [NoteFile] = [] {
        didSet { rebuildWikiIndex() }
    }
    @Published var selectedFolderURL: URL?
    @Published var isLoading = false
    @Published var lastExternalChange: ExternalChangeEvent?
    @Published private(set) var wikiIndexVersion = 0

    private var pathIndexLower: [String: NoteFile] = [:]
    private var basenameIndexLower: [String: [NoteFile]] = [:]
    private var canonicalByNoteID: [UUID: String] = [:]
    private var suggestionsAll: [WikiLinkSuggestion] = []
    private var suggestionsAllLower: [(suggestion: WikiLinkSuggestion, lowerTarget: String)] = []

    private let allowedExtensions = NotePathNaming.validExtensionSet

    /// Per-file cap for the full-content search index (and deep-match
    /// snippets). Keeps memory bounded for pathological files; ordinary
    /// notes fit entirely.
    static let searchIndexMaxBytes = 256 * 1024

    /// Derives the ~2 KB row preview from (possibly much larger) raw content.
    static func makeContentPreview(fromRawContent rawContent: String, isOrgFile: Bool) -> String {
        let head = String(rawContent.prefix(2048))
        if isOrgFile {
            let filteredLines = head.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#+") }
            return filteredLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return head.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private let folderBookmarkKey = "selectedFolderBookmark"
    private var fileWatcher: FileWatcher?
    private var discoveryTask: Task<Void, Never>?
    
    init() {
        if let testDir = ProcessInfo.processInfo.environment["NEONV_TEST_NOTES_DIR"] {
            selectedFolderURL = Self.canonicalFolderURL(fromPath: testDir)
            discoveryTask = Task { await discoverFiles() }
        } else if let cliPath = Self.launchFolderArgument() {
            setFolder(from: cliPath)
        } else {
            loadSavedFolder()
        }
    }

    /// Canonicalizes a folder path with realpath(3) so it matches the paths
    /// FileManager's enumerator and FSEvents report. URL.resolvingSymlinksInPath()
    /// is NOT equivalent: it strips the /private prefix that those APIs include,
    /// which previously mangled relative paths for symlinked folders like /tmp.
    static func canonicalFolderURL(fromPath path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        guard let resolved = realpath(expanded, nil) else {
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    /// The folder path passed as the first command-line argument, if any.
    static func launchFolderArgument() -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard args.count > 1 else { return nil }
        let firstArg = args[1]
        if firstArg.hasPrefix("-") { return nil }
        return firstArg
    }

    func setFolder(from path: String) {
        let url = Self.canonicalFolderURL(fromPath: path)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            Task { @MainActor in
                self.showInvalidPathAlert(path: path)
            }
            return
        }

        saveFolder(url)
        selectedFolderURL = url
        discoveryTask?.cancel()
        discoveryTask = Task {
            await discoverFiles()
        }
    }

    private func showInvalidPathAlert(path: String) {
        let present = {
            let alert = NSAlert()
            alert.messageText = "Invalid Folder Path"
            alert.informativeText = "The path \"\(path)\" is not a valid folder.\n\nPlease provide a path to an existing directory."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }

        if NSApp.isRunning {
            present()
        } else {
            // setFolder can run during app init (command-line folder argument).
            // A modal alert presented before the run loop starts is never shown,
            // so wait until the app is actually running.
            Task { @MainActor in
                while !NSApp.isRunning {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                present()
            }
        }
    }
    
    private func startWatching() {
        stopWatching()
        
        guard let folderURL = selectedFolderURL else { return }
        
        let watcher = FileWatcher(path: folderURL.path, debounceInterval: 0.15)
        watcher.delegate = self
        watcher.start()
        fileWatcher = watcher
    }
    
    private func stopWatching() {
        fileWatcher?.stop()
        fileWatcher = nil
    }
    
    nonisolated func fileWatcher(_ watcher: FileWatcher, didObserveChanges events: [FileChangeEvent]) {
        Task { @MainActor in
            self.handleFileChanges(events)
        }
    }
    
    /// Content hashes of files last written by this app, keyed by URL.
    /// Used to detect whether an FSEvent represents a genuine external change
    /// or just cloud sync services (Dropbox, iCloud) re-touching the file.
    private var lastSavedContentHash: [URL: String] = [:]

    /// URLs of files recently saved by this app (short-lived, for quick filtering).
    private var recentlySavedURLs: Set<URL> = []

    /// Marks both the old and new URLs as recently-saved so the file watcher
    /// ignores the rename event, and transfers the content hash to the new URL.
    func markAsRenamedLocally(oldURL: URL, newURL: URL) {
        recentlySavedURLs.insert(oldURL)
        recentlySavedURLs.insert(newURL)
        if let hash = lastSavedContentHash[oldURL] {
            lastSavedContentHash[newURL] = hash
            lastSavedContentHash.removeValue(forKey: oldURL)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            self.recentlySavedURLs.remove(oldURL)
            self.recentlySavedURLs.remove(newURL)
        }
    }

    func markAsSavedLocally(_ url: URL, content: String? = nil) {
        recentlySavedURLs.insert(url)
        if let content = content, let data = content.data(using: .utf8) {
            lastSavedContentHash[url] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            self.recentlySavedURLs.remove(url)
        }
    }

    /// Returns true if the file content at `url` differs from what we last saved.
    private func hasContentChangedExternally(at url: URL) -> Bool {
        guard let savedHash = lastSavedContentHash[url] else {
            // No record of saving this file — treat as external
            return true
        }
        guard let data = try? Data(contentsOf: url) else {
            return true
        }
        let currentHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return currentHash != savedHash
    }

    private func handleFileChanges(_ events: [FileChangeEvent]) {
        guard let folderURL = selectedFolderURL else { return }

        for event in events {
            switch event {
            case .created(let url):
                let existed = notes.contains { $0.url == url }
                addOrUpdateNote(at: url, folderURL: folderURL)
                // Atomic saves (vim, VS Code, etc.) appear as rename/create, not modify.
                // Treat a "create" on an already-tracked file as a modification.
                if existed && !recentlySavedURLs.contains(url) && hasContentChangedExternally(at: url) {
                    lastExternalChange = ExternalChangeEvent(url: url, kind: .modified)
                }

            case .modified(let url):
                addOrUpdateNote(at: url, folderURL: folderURL)
                if !recentlySavedURLs.contains(url) && hasContentChangedExternally(at: url) {
                    lastExternalChange = ExternalChangeEvent(url: url, kind: .modified)
                }

            case .deleted(let url):
                notes.removeAll { $0.url == url }
                if !recentlySavedURLs.contains(url) {
                    lastExternalChange = ExternalChangeEvent(url: url, kind: .deleted)
                }

            case .renamed(let oldURL, let newURL):
                if let oldURL = oldURL {
                    notes.removeAll { $0.url == oldURL }
                    if !recentlySavedURLs.contains(oldURL) {
                        lastExternalChange = ExternalChangeEvent(url: oldURL, kind: .deleted)
                    }
                }
                if let newURL = newURL {
                    let existed = notes.contains { $0.url == newURL }
                    addOrUpdateNote(at: newURL, folderURL: folderURL)
                    if existed && !recentlySavedURLs.contains(newURL) {
                        lastExternalChange = ExternalChangeEvent(url: newURL, kind: .modified)
                    }
                }
            }
        }

        notes.sort(by: Self.noteOrdering)

        // Keep the cache fresh after incremental updates.
        if let folderURL = selectedFolderURL {
            MetadataCache.save(notes, for: folderURL)
        }
    }

    /// Newest first; ties broken by path so the order is deterministic for
    /// notes that share a modification date.
    static func noteOrdering(_ lhs: NoteFile, _ rhs: NoteFile) -> Bool {
        if lhs.modificationDate != rhs.modificationDate {
            return lhs.modificationDate > rhs.modificationDate
        }
        return lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
    }

    private func addOrUpdateNote(at url: URL, folderURL: URL) {
        let ext = url.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        
        do {
            let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard resourceValues.isRegularFile == true else { return }
            
            let modDate = resourceValues.contentModificationDate ?? Date()
            let relativePath = url.path.replacingOccurrences(of: folderURL.path + "/", with: "")
            let title = Self.readFirstLineStatic(from: url)
            let rawContent = Self.readRawContentStatic(from: url, maxBytes: Self.searchIndexMaxBytes)
            let isOrgFile = ext == "org"
            let contentPreview = Self.makeContentPreview(fromRawContent: rawContent, isOrgFile: isOrgFile)
            let tags = Self.parseTagsStatic(from: String(rawContent.prefix(2048)), isOrgFile: isOrgFile)

            let writable = FileManager.default.isWritableFile(atPath: url.path)
            if let index = notes.firstIndex(where: { $0.url == url }) {
                notes[index].updateContent(title: title, contentPreview: contentPreview,
                                           indexedContent: rawContent, modificationDate: modDate, tags: tags)
                notes[index].isReadOnly = !writable
            } else {
                let note = NoteFile(
                    url: url,
                    relativePath: relativePath,
                    modificationDate: modDate,
                    title: title,
                    contentPreview: contentPreview,
                    indexedContent: rawContent,
                    isReadOnly: !writable,
                    tags: tags
                )
                notes.append(note)
            }
        } catch {
            return
        }
    }
    
    @discardableResult
    func renameNote(id: UUID, newName: String) throws -> NoteFile {
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            throw NSError(domain: "NoteStore", code: 0, userInfo: [NSLocalizedDescriptionKey: "Note not found."])
        }
        let note = notes[index]
        guard !note.isUnsaved else {
            throw NSError(domain: "NoteStore", code: 0, userInfo: [NSLocalizedDescriptionKey: "Cannot rename an unsaved note."])
        }

        let sanitized = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else {
            throw NSError(domain: "NoteStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Filename cannot be empty."])
        }

        let newFileName: String
        if NotePathNaming.hasValidExtension(sanitized) {
            newFileName = sanitized
        } else {
            let ext = note.url.pathExtension
            newFileName = sanitized.hasSuffix(".\(ext)") ? sanitized : "\(sanitized).\(ext)"
        }
        let newURL = note.url.deletingLastPathComponent().appendingPathComponent(newFileName)

        guard newURL != note.url else { return note }
        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            throw NSError(domain: "NoteStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "A file named \"\(newFileName)\" already exists."])
        }

        markAsRenamedLocally(oldURL: note.url, newURL: newURL)
        try FileManager.default.moveItem(at: note.url, to: newURL)

        let relativePath: String
        if let folder = selectedFolderURL {
            relativePath = newURL.path.replacingOccurrences(of: folder.path + "/", with: "")
        } else {
            relativePath = newFileName
        }

        let resourceValues = try? newURL.resourceValues(forKeys: [.contentModificationDateKey])
        let modDate = resourceValues?.contentModificationDate ?? note.modificationDate

        let renamed = NoteFile(
            id: note.id,
            url: newURL,
            relativePath: relativePath,
            modificationDate: modDate,
            title: note.title,
            contentPreview: note.contentPreview,
            indexedContent: note.indexedContent,
            tags: note.tags
        )
        notes[index] = renamed
        return renamed
    }

    func deleteNote(id: UUID) throws {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let note = notes[index]

        if !note.isUnsaved {
            try FileManager.default.trashItem(at: note.url, resultingItemURL: nil)
        }

        notes.remove(at: index)
    }

    func createNewUnsavedNote() -> NoteFile? {
        guard let folderURL = selectedFolderURL else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let ext = AppSettings.shared.defaultExtension.rawValue
        let suffix = UUID().uuidString.prefix(3).lowercased()
        let fileName = "untitled-\(timestamp)-\(suffix).\(ext)"
        var fileURL = folderURL.appendingPathComponent(fileName)

        // Ensure in-memory uniqueness (extremely unlikely but defensive)
        while notes.contains(where: { $0.url == fileURL }) {
            let retrySuffix = UUID().uuidString.prefix(3).lowercased()
            let retryName = "untitled-\(timestamp)-\(retrySuffix).\(ext)"
            fileURL = folderURL.appendingPathComponent(retryName)
        }

        let relativePath = fileURL.lastPathComponent
        let note = NoteFile(
            url: fileURL,
            relativePath: relativePath,
            modificationDate: Date(),
            title: "",
            contentPreview: "",
            isUnsaved: true
        )

        notes.insert(note, at: 0)
        return note
    }
    
    /// If the note's URL already exists on disk, reassign it to a unique filename.
    /// Returns the new URL if reassigned, or nil if no conflict.
    func resolveFirstSaveCollision(id: UUID) -> URL? {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return nil }
        let note = notes[idx]
        guard FileManager.default.fileExists(atPath: note.url.path) else { return nil }

        let dir = note.url.deletingLastPathComponent()
        let ext = note.url.pathExtension
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        var candidate: URL
        repeat {
            let suffix = UUID().uuidString.prefix(3).lowercased()
            candidate = dir.appendingPathComponent("untitled-\(timestamp)-\(suffix).\(ext)")
        } while FileManager.default.fileExists(atPath: candidate.path)
            || notes.contains(where: { $0.url == candidate })

        let relativePath = selectedFolderURL.map {
            candidate.path.replacingOccurrences(of: $0.path + "/", with: "")
        } ?? candidate.lastPathComponent

        notes[idx] = NoteFile(
            id: note.id, url: candidate, relativePath: relativePath,
            modificationDate: Date(), title: note.title,
            contentPreview: note.contentPreview, isUnsaved: true
        )
        return candidate
    }

    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your notes folder"
        panel.prompt = "Select"
        
        if panel.runModal() == .OK, let panelURL = panel.url {
            let url = Self.canonicalFolderURL(fromPath: panelURL.path)
            saveFolder(url)
            selectedFolderURL = url
            discoveryTask?.cancel()
            discoveryTask = Task {
                await discoverFiles()
            }
        }
    }
    
    func discoverFiles() async {
        guard let folderURL = selectedFolderURL else {
            notes = []
            return
        }

        isLoading = true
        stopWatching()

        // Show cached notes immediately for a fast warm start.
        if notes.isEmpty, let cached = MetadataCache.load(for: folderURL) {
            notes = cached.map { cn in
                NoteFile(
                    url: folderURL.appendingPathComponent(cn.relativePath),
                    relativePath: cn.relativePath,
                    modificationDate: cn.modificationDate,
                    title: cn.title,
                    contentPreview: cn.contentPreview,
                    tags: cn.tags
                )
            }
        }

        let extensions = allowedExtensions
        let flag = CancellationFlag()
        let discoveredNotes: [NoteFile] = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = NoteStore.enumerateNotes(
                        in: folderURL,
                        allowedExtensions: extensions,
                        isCancelled: { flag.isCancelled }
                    )
                    continuation.resume(returning: result)
                }
            }
        } onCancel: {
            flag.isCancelled = true
        }

        guard !Task.isCancelled else { return }

        notes = discoveredNotes
        isLoading = false
        startWatching()

        // Persist fresh metadata for next launch.
        MetadataCache.save(discoveredNotes, for: folderURL)
    }

    /// Directories to skip during enumeration (common junk directories)
    private static let junkDirectories: Set<String> = [
        ".git", "node_modules", ".build", "__pycache__", ".svn", ".hg",
        "venv", ".venv", "target", "build", "dist", ".gradle", ".idea",
        "vendor", "Pods", "DerivedData", ".tox", ".pytest_cache",
        ".mypy_cache", ".ruff_cache", "__MACOSX"
    ]

    /// Enumerates files and reads metadata off the main thread
    private static func enumerateNotes(in folderURL: URL, allowedExtensions: Set<String>, isCancelled: @Sendable () -> Bool = { false }) -> [NoteFile] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let folderPath = folderURL.path + "/"
        var result: [NoteFile] = []
        result.reserveCapacity(1024)

        for case let fileURL as URL in enumerator {
            if isCancelled() { return [] }

            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey, .isDirectoryKey])

                // Skip junk directories early using skipDescendants
                if resourceValues.isDirectory == true {
                    let dirName = fileURL.lastPathComponent
                    if junkDirectories.contains(dirName) {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                // Skip non-regular files
                guard resourceValues.isRegularFile == true else { continue }

                // Filter by extension early
                let ext = fileURL.pathExtension.lowercased()
                guard allowedExtensions.contains(ext) else { continue }

                let modDate = resourceValues.contentModificationDate ?? Date.distantPast
                let relativePath = fileURL.path.replacingOccurrences(of: folderPath, with: "")
                let title = readFirstLineStatic(from: fileURL)
                let rawContent = readRawContentStatic(from: fileURL, maxBytes: searchIndexMaxBytes)
                let isOrgFile = ext == "org"
                let contentPreview = makeContentPreview(fromRawContent: rawContent, isOrgFile: isOrgFile)
                let tags = parseTagsStatic(from: String(rawContent.prefix(2048)), isOrgFile: isOrgFile)

                let writable = fileManager.isWritableFile(atPath: fileURL.path)
                let note = NoteFile(
                    url: fileURL,
                    relativePath: relativePath,
                    modificationDate: modDate,
                    title: title,
                    contentPreview: contentPreview,
                    indexedContent: rawContent,
                    isReadOnly: !writable,
                    tags: tags
                )
                result.append(note)
            } catch {
                continue
            }
        }

        result.sort(by: noteOrdering)
        return result
    }

    static func parseTagsStatic(from content: String, isOrgFile: Bool = false) -> [String] {
        let lines = content.components(separatedBy: .newlines)
        for line in lines.prefix(10) { // Only check first 10 lines
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Org-mode format: #+FILETAGS: :tag1:tag2:tag3:
            if trimmed.uppercased().hasPrefix("#+FILETAGS:") {
                let tagPart = String(trimmed.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                let tags = tagPart.components(separatedBy: ":")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                return tags
            }

            // Standard format for non-org files: Tags: tag1, tag2, tag3
            if !isOrgFile && (trimmed.lowercased().hasPrefix("tags:") || trimmed.lowercased().hasPrefix("tag:")) {
                guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }
                let tagPart = String(trimmed[trimmed.index(after: colonIndex)...])
                let tags = tagPart.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                return tags
            }
        }
        return []
    }

    private static func readFirstLineStatic(from url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 512) else { return "" }
        guard let content = String(data: data, encoding: .utf8) else { return "" }

        let isOrgFile = url.pathExtension.lowercased() == "org"
        
        // For org files, look for #+TITLE: first
        if isOrgFile {
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.uppercased().hasPrefix("#+TITLE:") {
                    let title = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                    if !title.isEmpty {
                        return title
                    }
                }
            }
        }
        
        // Find first non-empty, non-metadata line
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                // Skip org metadata lines
                if isOrgFile && trimmed.hasPrefix("#+") {
                    continue
                }
                return trimmed
            }
        }
        return ""
    }

    private static func readRawContentStatic(from url: URL, maxBytes: Int = 2048) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    private func normalizedWikiTarget(_ target: String) -> String {
        let trimmed = target
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return "" }

        return NotePathNaming.splitRecognizedExtension(from: trimmed).base
    }

    private func relativePathWithoutExtension(for note: NoteFile) -> String {
        let ns = note.relativePath as NSString
        return ns.deletingPathExtension
    }

    private func basenameWithoutExtension(for note: NoteFile) -> String {
        note.url.deletingPathExtension().lastPathComponent
    }

    func resolveWikiLink(_ target: String) -> WikiLinkResolution {
        let normalized = normalizedWikiTarget(target)
        guard !normalized.isEmpty else { return .missing(normalized) }

        let lower = normalized.lowercased()
        if normalized.contains("/") {
            if let note = pathIndexLower[lower] {
                return .resolved(note)
            }
            return .missing(normalized)
        }

        guard let matches = basenameIndexLower[lower], !matches.isEmpty else {
            return .missing(normalized)
        }

        if matches.count == 1, let note = matches.first {
            return .resolved(note)
        }
        return .ambiguous(matches)
    }

    func canonicalWikiTarget(for note: NoteFile) -> String {
        if let canonical = canonicalByNoteID[note.id] {
            return canonical
        }

        let basename = basenameWithoutExtension(for: note)
        if normalizedWikiTarget(basename).isEmpty {
            return relativePathWithoutExtension(for: note)
        }
        return basename
    }

    func wikiLinkSuggestions(prefix: String, limit: Int = 30) -> [WikiLinkSuggestion] {
        let cappedLimit = max(0, limit)
        guard cappedLimit > 0 else { return [] }

        let normalizedPrefix = normalizedWikiTarget(prefix).lowercased()
        guard !normalizedPrefix.isEmpty else {
            return Array(suggestionsAll.prefix(cappedLimit))
        }

        var seen = Set<String>()
        var candidates: [WikiLinkSuggestion] = []

        // Reuse the same matching rules as the main Cmd+L search path.
        let prefixTerms = NoteFile.searchTerms(from: normalizedPrefix)
        for note in notes where note.matches(allLowercasedTerms: prefixTerms) {
            let canonical = canonicalByNoteID[note.id] ?? canonicalWikiTarget(for: note)
            guard isSafeWikiLinkTargetForInsertion(canonical) else { continue }
            let lowerCanonical = canonical.lowercased()
            guard seen.insert(lowerCanonical).inserted else { continue }

            candidates.append(
                WikiLinkSuggestion(
                    insertTarget: canonical,
                    display: canonical,
                    detailPath: note.relativePath
                )
            )
        }

        // Fallback to canonical-target contains matching when content-based search yields no hits.
        if candidates.isEmpty {
            for entry in suggestionsAllLower where entry.lowerTarget.contains(normalizedPrefix) {
                guard isSafeWikiLinkTargetForInsertion(entry.suggestion.insertTarget) else { continue }
                guard seen.insert(entry.lowerTarget).inserted else { continue }
                candidates.append(entry.suggestion)
            }
        }

        let ranked = candidates.sorted { lhs, rhs in
            let lhsLower = lhs.insertTarget.lowercased()
            let rhsLower = rhs.insertTarget.lowercased()
            let lhsPrefix = lhsLower.hasPrefix(normalizedPrefix)
            let rhsPrefix = rhsLower.hasPrefix(normalizedPrefix)
            if lhsPrefix != rhsPrefix {
                return lhsPrefix
            }
            return lhs.display.localizedCaseInsensitiveCompare(rhs.display) == .orderedAscending
        }

        return Array(ranked.prefix(cappedLimit))
    }

    private func rebuildWikiIndex() {
        var newPathIndexLower: [String: NoteFile] = [:]
        var newBasenameIndexLower: [String: [NoteFile]] = [:]
        var newCanonicalByNoteID: [UUID: String] = [:]

        for note in notes {
            let pathKey = relativePathWithoutExtension(for: note).lowercased()
            newPathIndexLower[pathKey] = note

            let basenameKey = basenameWithoutExtension(for: note).lowercased()
            newBasenameIndexLower[basenameKey, default: []].append(note)
        }

        for (key, var list) in newBasenameIndexLower {
            list.sort {
                $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
            }
            newBasenameIndexLower[key] = list

            if list.count == 1, let note = list.first {
                newCanonicalByNoteID[note.id] = basenameWithoutExtension(for: note)
            } else {
                for note in list {
                    newCanonicalByNoteID[note.id] = relativePathWithoutExtension(for: note)
                }
            }
        }

        var suggestionByKey: [String: WikiLinkSuggestion] = [:]
        for note in notes {
            let canonical = newCanonicalByNoteID[note.id] ?? basenameWithoutExtension(for: note)
            guard isSafeWikiLinkTargetForInsertion(canonical) else { continue }
            let key = canonical.lowercased()
            let candidate = WikiLinkSuggestion(
                insertTarget: canonical,
                display: canonical,
                detailPath: note.relativePath
            )

            if let existing = suggestionByKey[key] {
                if candidate.detailPath.localizedCaseInsensitiveCompare(existing.detailPath) == .orderedAscending {
                    suggestionByKey[key] = candidate
                }
            } else {
                suggestionByKey[key] = candidate
            }
        }

        let sortedSuggestions = suggestionByKey.values.sorted { lhs, rhs in
            lhs.display.localizedCaseInsensitiveCompare(rhs.display) == .orderedAscending
        }
        let sortedSuggestionsLower = sortedSuggestions.map { suggestion in
            (suggestion: suggestion, lowerTarget: suggestion.insertTarget.lowercased())
        }

        pathIndexLower = newPathIndexLower
        basenameIndexLower = newBasenameIndexLower
        canonicalByNoteID = newCanonicalByNoteID
        suggestionsAll = sortedSuggestions
        suggestionsAllLower = sortedSuggestionsLower
        wikiIndexVersion &+= 1
    }
    
    private func saveFolder(_ url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: folderBookmarkKey)
        } catch {
            UserDefaults.standard.set(url.absoluteString, forKey: "selectedNotesFolder")
        }
    }
    
    private func loadSavedFolder() {
        if let bookmarkData = UserDefaults.standard.data(forKey: folderBookmarkKey) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                // Required under the sandbox; a harmless no-op without it.
                // Don't gate on the return value — bookmarks created by older
                // sandboxed builds report false here once the sandbox is gone.
                _ = url.startAccessingSecurityScopedResource()
                selectedFolderURL = url
                discoveryTask?.cancel()
                discoveryTask = Task {
                    await discoverFiles()
                }
            }
        } else if let storedPath = UserDefaults.standard.string(forKey: "selectedNotesFolder"),
                  let url = URL(string: storedPath) {
            selectedFolderURL = url
            discoveryTask?.cancel()
            discoveryTask = Task {
                await discoverFiles()
            }
        }
    }
}
