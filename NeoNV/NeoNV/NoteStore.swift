import Foundation
import AppKit
import CoreServices
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
    var isUnsaved: Bool = false

    /// Pre-computed lowercased strings for fast search matching
    private(set) var searchTitle: String = ""
    private(set) var searchPath: String = ""
    private(set) var searchPreview: String = ""

    init(url: URL, relativePath: String, modificationDate: Date, title: String, contentPreview: String = "", isUnsaved: Bool = false) {
        self.id = UUID()
        self.url = url
        self.relativePath = relativePath
        self.modificationDate = modificationDate
        self.title = title
        self.contentPreview = contentPreview
        self.isUnsaved = isUnsaved
        self.searchTitle = title.lowercased()
        self.searchPath = relativePath.lowercased()
        self.searchPreview = contentPreview.lowercased()
    }

    func matches(query: String) -> Bool {
        let lowercasedQuery = query.lowercased()
        return searchTitle.contains(lowercasedQuery) ||
               searchPath.contains(lowercasedQuery) ||
               searchPreview.contains(lowercasedQuery)
    }

    mutating func updateContent(title: String, contentPreview: String, modificationDate: Date) {
        self.title = title
        self.contentPreview = contentPreview
        self.modificationDate = modificationDate
        self.searchTitle = title.lowercased()
        self.searchPreview = contentPreview.lowercased()
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
    @Published var notes: [NoteFile] = []
    @Published var selectedFolderURL: URL?
    @Published var isLoading = false
    @Published var lastExternalChange: ExternalChangeEvent?

    private let allowedExtensions: Set<String> = ["txt", "md", "markdown", "org", "text"]
    private let folderBookmarkKey = "selectedFolderBookmark"
    private var fileWatcher: FileWatcher?
    private var discoveryTask: Task<Void, Never>?
    
    init() {
        if let cliPath = Self.parseCommandLineFolder() {
            setFolder(from: cliPath)
        } else {
            loadSavedFolder()
        }
    }

    private static func parseCommandLineFolder() -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard args.count > 1 else { return nil }
        let firstArg = args[1]
        if firstArg.hasPrefix("-") { return nil }
        return firstArg
    }

    func setFolder(from path: String) {
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

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
        let alert = NSAlert()
        alert.messageText = "Invalid Folder Path"
        alert.informativeText = "The path \"\(path)\" is not a valid folder.\n\nPlease provide a path to an existing directory."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
    private var lastSavedContentHash: [URL: Int] = [:]

    /// URLs of files recently saved by this app (short-lived, for quick filtering).
    private var recentlySavedURLs: Set<URL> = []

    func markAsSavedLocally(_ url: URL, content: String? = nil) {
        recentlySavedURLs.insert(url)
        if let content = content {
            lastSavedContentHash[url] = content.hashValue
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
        guard let data = try? Data(contentsOf: url),
              let currentContent = String(data: data, encoding: .utf8) else {
            return true
        }
        return currentContent.hashValue != savedHash
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

        notes.sort { $0.modificationDate > $1.modificationDate }
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
            let title = readFirstLine(from: url)
            let contentPreview = readContentPreview(from: url)
            
            if let index = notes.firstIndex(where: { $0.url == url }) {
                notes[index].updateContent(title: title, contentPreview: contentPreview, modificationDate: modDate)
            } else {
                let note = NoteFile(
                    url: url,
                    relativePath: relativePath,
                    modificationDate: modDate,
                    title: title,
                    contentPreview: contentPreview
                )
                notes.append(note)
            }
        } catch {
            return
        }
    }
    
    func deleteNote(id: UUID) throws {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let note = notes[index]

        if !note.isUnsaved {
            try FileManager.default.removeItem(at: note.url)
        }

        notes.remove(at: index)
    }

    func createNewUnsavedNote() -> NoteFile? {
        guard let folderURL = selectedFolderURL else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let ext = AppSettings.shared.defaultExtension.rawValue
        let fileName = "untitled-\(timestamp).\(ext)"
        let fileURL = folderURL.appendingPathComponent(fileName)
        
        let note = NoteFile(
            url: fileURL,
            relativePath: fileName,
            modificationDate: Date(),
            title: "",
            contentPreview: "",
            isUnsaved: true
        )
        
        notes.insert(note, at: 0)
        return note
    }
    
    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your notes folder"
        panel.prompt = "Select"
        
        if panel.runModal() == .OK, let url = panel.url {
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
                let contentPreview = readContentPreviewStatic(from: fileURL)

                let note = NoteFile(
                    url: fileURL,
                    relativePath: relativePath,
                    modificationDate: modDate,
                    title: title,
                    contentPreview: contentPreview
                )
                result.append(note)
            } catch {
                continue
            }
        }

        result.sort { $0.modificationDate > $1.modificationDate }
        return result
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

    private static func readContentPreviewStatic(from url: URL, maxBytes: Int = 2048) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes) else { return "" }
        guard let content = String(data: data, encoding: .utf8) else { return "" }
        
        // For org files, filter out metadata lines (#+KEY:)
        if url.pathExtension.lowercased() == "org" {
            let filteredLines = content.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#+") }
            return filteredLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func readFirstLine(from url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: 256) else { return "" }
        guard let content = String(data: data, encoding: .utf8) else { return "" }

        // Find first non-empty line
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    private func readContentPreview(from url: URL, maxBytes: Int = 2048) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: maxBytes) else { return "" }
        guard let content = String(data: data, encoding: .utf8) else { return "" }

        // For org files, filter out metadata lines (#+KEY:)
        if url.pathExtension.lowercased() == "org" {
            let filteredLines = content.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#+") }
            return filteredLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
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
                if url.startAccessingSecurityScopedResource() {
                    selectedFolderURL = url
                    discoveryTask?.cancel()
                    discoveryTask = Task {
                        await discoverFiles()
                    }
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
