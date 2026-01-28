import Foundation
import AppKit

struct NoteFile: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let relativePath: String
    var modificationDate: Date
    var title: String
    var contentPreview: String
    var isUnsaved: Bool = false
    
    init(url: URL, relativePath: String, modificationDate: Date, title: String, contentPreview: String = "", isUnsaved: Bool = false) {
        self.id = UUID()
        self.url = url
        self.relativePath = relativePath
        self.modificationDate = modificationDate
        self.title = title
        self.contentPreview = contentPreview
        self.isUnsaved = isUnsaved
    }
    
    func matches(query: String) -> Bool {
        let lowercasedQuery = query.lowercased()
        return title.lowercased().contains(lowercasedQuery) ||
               relativePath.lowercased().contains(lowercasedQuery) ||
               contentPreview.lowercased().contains(lowercasedQuery)
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

@MainActor
class NoteStore: ObservableObject {
    @Published var notes: [NoteFile] = []
    @Published var selectedFolderURL: URL?
    @Published var isLoading = false
    
    private let allowedExtensions: Set<String> = ["txt", "md", "markdown", "org", "text"]
    private let folderBookmarkKey = "selectedFolderBookmark"
    
    init() {
        loadSavedFolder()
    }
    
    func createNewUnsavedNote() -> NoteFile? {
        guard let folderURL = selectedFolderURL else { return nil }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let fileName = "untitled-\(timestamp).md"
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
            Task {
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
        defer { isLoading = false }
        
        var discoveredNotes: [NoteFile] = []
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            notes = []
            return
        }
        
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }
            
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard resourceValues.isRegularFile == true else { continue }
                
                let modDate = resourceValues.contentModificationDate ?? Date.distantPast
                let relativePath = fileURL.path.replacingOccurrences(of: folderURL.path + "/", with: "")
                let title = readFirstLine(from: fileURL)
                let contentPreview = readContentPreview(from: fileURL)

                let note = NoteFile(
                    url: fileURL,
                    relativePath: relativePath,
                    modificationDate: modDate,
                    title: title,
                    contentPreview: contentPreview
                )
                discoveredNotes.append(note)
            } catch {
                continue
            }
        }
        
        discoveredNotes.sort { $0.modificationDate > $1.modificationDate }
        notes = discoveredNotes
    }
    
    private func readFirstLine(from url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: 256) else { return "" }
        guard let content = String(data: data, encoding: .utf8) else { return "" }

        let firstLine = content.components(separatedBy: .newlines).first ?? ""
        return firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readContentPreview(from url: URL, maxBytes: Int = 2048) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: maxBytes) else { return "" }
        guard let content = String(data: data, encoding: .utf8) else { return "" }

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
                    Task {
                        await discoverFiles()
                    }
                }
            }
        } else if let storedPath = UserDefaults.standard.string(forKey: "selectedNotesFolder"),
                  let url = URL(string: storedPath) {
            selectedFolderURL = url
            Task {
                await discoverFiles()
            }
        }
    }
}
