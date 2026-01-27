import SwiftUI

enum FocusedField: Hashable {
    case search
    case noteList
    case editor
}

struct ContentView: View {
    @StateObject private var noteStore = NoteStore()
    @State private var searchText = ""
    @State private var selectedNoteID: UUID?
    @State private var editorContent = ""
    @State private var isDirty = false
    @State private var saveTask: Task<Void, Never>?
    @State private var isLoadingNote = false
    @State private var saveError: SaveError?
    @FocusState private var focusedField: FocusedField?

    struct SaveError: Identifiable {
        let id = UUID()
        let fileURL: URL
        let error: Error
        let content: String
    }

    private var filteredNotes: [NoteFile] {
        if searchText.isEmpty {
            return noteStore.notes
        } else {
            return noteStore.notes.filter { $0.matches(query: searchText) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(
                text: $searchText,
                focusedField: _focusedField,
                matchCount: filteredNotes.count,
                onNavigateToList: navigateToList,
                onCreateNote: createNewNote,
                onClearSearch: clearSearch
            )
            
            Divider()
            
            if noteStore.selectedFolderURL == nil {
                EmptyStateView(onSelectFolder: noteStore.selectFolder)
            } else {
                HSplitView {
                    NoteListView(
                        notes: filteredNotes,
                        selectedNoteID: $selectedNoteID,
                        focusedField: _focusedField,
                        isLoading: noteStore.isLoading,
                        onTabToEditor: { focusedField = .editor },
                        onShiftTabToSearch: { focusedField = .search },
                        onEnterToEditor: { focusedField = .editor }
                    )
                    .frame(minWidth: 150, idealWidth: 200, maxWidth: 350)
                    
                    EditorView(
                        content: $editorContent,
                        focusedField: _focusedField,
                        onShiftTab: { focusedField = .noteList },
                        onEscape: { focusedField = .noteList }
                    )
                    .frame(minWidth: 300)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            focusedField = .search
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if isDirty {
                    Circle()
                        .fill(.orange)
                        .frame(width: 8, height: 8)
                        .help("Unsaved changes")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button(action: noteStore.selectFolder) {
                    Image(systemName: "folder")
                }
                .help("Select notes folder")
            }
        }
        .onChange(of: selectedNoteID) { _, newID in
            loadSelectedNote(id: newID)
        }
        .onChange(of: editorContent) { _, _ in
            scheduleAutoSave()
        }
        .onChange(of: searchText) { _, newText in
            autoSelectTopMatch()
        }
        .alert(item: $saveError) { error in
            Alert(
                title: Text("Save Failed"),
                message: Text("Failed to save \(error.fileURL.lastPathComponent):\n\n\(error.error.localizedDescription)"),
                primaryButton: .default(Text("Retry")) {
                    Task {
                        await retrySave(error: error)
                    }
                },
                secondaryButton: .default(Text("More Options...")) {
                    showSaveErrorSheet(error: error)
                }
            )
        }
        .disabled(saveError != nil)
    }
    
    private func autoSelectTopMatch() {
        if searchText.isEmpty {
            // When clearing search, preserve current selection if it's still in the list
            if let currentID = selectedNoteID,
               noteStore.notes.contains(where: { $0.id == currentID }) {
                // Keep current selection
                return
            }
        } else {
            // When typing, auto-select the first match
            if let firstMatch = filteredNotes.first {
                selectedNoteID = firstMatch.id
            }
        }
    }

    private func loadSelectedNote(id: UUID?) {
        guard let id = id,
              let note = noteStore.notes.first(where: { $0.id == id }) else {
            editorContent = ""
            isDirty = false
            return
        }

        isLoadingNote = true
        Task {
            do {
                let content = try await loadFileAsync(url: note.url)
                await MainActor.run {
                    editorContent = content
                    isDirty = false
                    isLoadingNote = false
                }
            } catch {
                await MainActor.run {
                    editorContent = "Error loading file: \(error.localizedDescription)"
                    isDirty = false
                    isLoadingNote = false
                }
            }
        }
    }
    
    private func loadFileAsync(url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try String(contentsOf: url, encoding: .utf8)
        }.value
    }
    
    private func navigateToList() {
        if selectedNoteID == nil, let firstNote = filteredNotes.first {
            selectedNoteID = firstNote.id
        }
        focusedField = .noteList
    }

    private func createNewNote() {
        guard let folderURL = noteStore.selectedFolderURL, !searchText.isEmpty else {
            return
        }

        let fileName = sanitizeFileName(searchText)
        let fileURL = folderURL.appendingPathComponent(fileName + ".md")

        let initialContent = searchText + "\n\n"

        Task {
            do {
                try await atomicWrite(content: initialContent, to: fileURL)

                await noteStore.discoverFiles()

                await MainActor.run {
                    searchText = ""
                    if let newNote = noteStore.notes.first(where: { $0.url == fileURL }) {
                        selectedNoteID = newNote.id
                        focusedField = .editor
                    }
                }
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Failed to Create Note"
                    alert.informativeText = "Could not create new note: \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }

    private func clearSearch() {
        searchText = ""
        selectedNoteID = nil
    }

    private func sanitizeFileName(_ name: String) -> String {
        var sanitized = name.lowercased()
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

        return sanitized
    }

    private func scheduleAutoSave() {
        guard selectedNoteID != nil, !isLoadingNote else { return }
        isDirty = true
        AppDelegate.shared.hasUnsavedChanges = true

        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await performSave()
        }
    }
    
    private func performSave() async {
        guard let id = selectedNoteID,
              let note = noteStore.notes.first(where: { $0.id == id }) else {
            return
        }

        let content = editorContent

        do {
            try await atomicWrite(content: content, to: note.url)
            await MainActor.run {
                isDirty = false
                saveError = nil
                AppDelegate.shared.hasUnsavedChanges = false
            }
        } catch {
            await MainActor.run {
                saveError = SaveError(fileURL: note.url, error: error, content: content)
                AppDelegate.shared.hasUnsavedChanges = true
            }
        }
    }
    
    private func atomicWrite(content: String, to url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let data = content.data(using: .utf8)!
            let tempURL = url.deletingLastPathComponent()
                .appendingPathComponent(".\(url.lastPathComponent).tmp")

            try data.write(to: tempURL, options: .atomic)

            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: url)
            }
        }.value
    }

    private func retrySave(error: SaveError) async {
        do {
            try await atomicWrite(content: error.content, to: error.fileURL)
            await MainActor.run {
                isDirty = false
                saveError = nil
                AppDelegate.shared.hasUnsavedChanges = false
            }
        } catch let writeError {
            await MainActor.run {
                saveError = SaveError(fileURL: error.fileURL, error: writeError, content: error.content)
                AppDelegate.shared.hasUnsavedChanges = true
            }
        }
    }

    private func showSaveErrorSheet(error: SaveError) {
        let alert = NSAlert()
        alert.messageText = "Save Failed"
        alert.informativeText = "Failed to save \(error.fileURL.lastPathComponent):\n\n\(error.error.localizedDescription)\n\nWhat would you like to do?"
        alert.alertStyle = .critical

        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Save Elsewhere...")
        alert.addButton(withTitle: "Copy to Clipboard")
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            Task {
                await retrySave(error: error)
            }
        case .alertSecondButtonReturn:
            saveToAlternateLocation(error: error)
        case .alertThirdButtonReturn:
            copyToClipboard(error: error)
        default:
            if response.rawValue == 1003 {
                showInFinder(error: error)
            }
        }
    }

    private func saveToAlternateLocation(error: SaveError) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = error.fileURL.lastPathComponent
        panel.message = "Choose a new location to save this file"

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    try await atomicWrite(content: error.content, to: url)
                    await MainActor.run {
                        saveError = nil
                        AppDelegate.shared.hasUnsavedChanges = false
                    }
                } catch let writeError {
                    await MainActor.run {
                        saveError = SaveError(fileURL: url, error: writeError, content: error.content)
                        AppDelegate.shared.hasUnsavedChanges = true
                    }
                }
            }
        }
    }

    private func copyToClipboard(error: SaveError) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(error.content, forType: .string)

        let alert = NSAlert()
        alert.messageText = "Content Copied"
        alert.informativeText = "The file content has been copied to the clipboard.\n\nThe save error persists - you should still resolve it."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showInFinder(error: SaveError) {
        NSWorkspace.shared.selectFile(error.fileURL.path, inFileViewerRootedAtPath: error.fileURL.deletingLastPathComponent().path)
    }
}

struct EmptyStateView: View {
    var onSelectFolder: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No folder selected")
                .font(.headline)
            
            Text("Select a folder containing your notes")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button("Select Folder...", action: onSelectFolder)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SearchBar: View {
    @Binding var text: String
    @FocusState var focusedField: FocusedField?
    var matchCount: Int
    var onNavigateToList: () -> Void
    var onCreateNote: () -> Void
    var onClearSearch: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search or create...", text: $text)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .search)
                .onKeyPress(.tab) {
                    onNavigateToList()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    onNavigateToList()
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    return .handled
                }
                .onKeyPress(.return) {
                    if matchCount > 0 {
                        onNavigateToList()
                    } else if !text.isEmpty {
                        onCreateNote()
                    }
                    return .handled
                }
                .onKeyPress(.escape) {
                    onClearSearch()
                    return .handled
                }

            if !text.isEmpty {
                Text(matchCount > 0 ? "\(matchCount) match\(matchCount == 1 ? "" : "es")" : "⏎ to create")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.trailing, 4)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct NoteListView: View {
    var notes: [NoteFile]
    @Binding var selectedNoteID: UUID?
    @FocusState var focusedField: FocusedField?
    var isLoading: Bool
    var onTabToEditor: () -> Void
    var onShiftTabToSearch: () -> Void
    var onEnterToEditor: () -> Void
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if notes.isEmpty {
                Text("No notes found")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(notes, selection: $selectedNoteID) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.displayTitle)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Text(note.relativePath)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .tag(note.id)
                }
                .listStyle(.sidebar)
                .focusable()
                .focused($focusedField, equals: .noteList)
                .onKeyPress { press in
                    if press.key == .tab && press.modifiers.contains(.shift) {
                        onShiftTabToSearch()
                        return .handled
                    }
                    if press.key == .tab {
                        onTabToEditor()
                        return .handled
                    }
                    if press.key == .return {
                        onEnterToEditor()
                        return .handled
                    }
                    return .ignored
                }
            }
        }
    }
}

struct EditorView: View {
    @Binding var content: String
    @FocusState var focusedField: FocusedField?
    var onShiftTab: (() -> Void)?
    var onEscape: (() -> Void)?
    
    var body: some View {
        PlainTextEditor(
            text: $content,
            onShiftTab: onShiftTab,
            onEscape: onEscape
        )
        .focused($focusedField, equals: .editor)
    }
}

#Preview {
    ContentView()
}
