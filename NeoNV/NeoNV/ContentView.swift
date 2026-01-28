import SwiftUI

enum FocusedField: Hashable {
    case search
    case noteList
    case editor
    case preview
}

struct ContentView: View {
    @ObservedObject var noteStore: NoteStore
    @State private var searchText = ""
    @State private var selectedNoteID: UUID?
    @State private var lastManualSelection: UUID?
    @State private var previousSearchWasEmpty = true
    @State private var editorContent = ""
    @State private var originalContent = ""
    @State private var isDirty = false
    @State private var saveTask: Task<Void, Never>?
    @State private var saveError: SaveError?
    @State private var unsavedNoteIDs: Set<UUID> = []
    @State private var showPreview = false
    @FocusState private var focusedField: FocusedField?

    struct SaveError: Identifiable {
        let id = UUID()
        let fileURL: URL
        let error: Error
        let content: String
    }

    private var filteredNotes: [NoteFile] {
        let baseNotes = searchText.isEmpty ? noteStore.notes : noteStore.notes.filter { $0.matches(query: searchText) }
        
        return baseNotes.map { note in
            var updatedNote = note
            updatedNote.isUnsaved = unsavedNoteIDs.contains(note.id)
            return updatedNote
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
                        onEnterToEditor: { focusedField = .editor },
                        onEscapeToSearch: { focusedField = .search }
                    )
                    .frame(minWidth: 150, idealWidth: 200, maxWidth: 350)

                    if showPreview {
                        MarkdownPreviewView(
                            content: editorContent,
                            fontSize: CGFloat(AppSettings.shared.fontSize),
                            onShiftTab: { focusedField = .noteList },
                            onTypeToEdit: { switchToEditor() }
                        )
                        .focused($focusedField, equals: .preview)
                        .frame(minWidth: 300)
                    } else {
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
        }
        .frame(minWidth: 600, minHeight: 400)
        .navigationTitle("neonv")
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
                Button(action: togglePreview) {
                    Image(systemName: showPreview ? "eye.fill" : "eye")
                }
                .help(showPreview ? "Hide preview (⌘P)" : "Show preview (⌘P)")
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
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            focusSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewNote)) { _ in
            createNewNoteFromShortcut()
        }
        .onReceive(NotificationCenter.default.publisher(for: .togglePreview)) { _ in
            togglePreview()
        }
    }

    private func focusSearch() {
        focusedField = .search
    }

    private func togglePreview() {
        showPreview.toggle()
        if showPreview {
            focusedField = .preview
        } else {
            focusedField = .editor
        }
    }

    private func switchToEditor() {
        showPreview = false
        focusedField = .editor
    }

    private func createNewNoteFromShortcut() {
        guard noteStore.selectedFolderURL != nil else { return }
        
        searchText = ""
        
        if let newNote = noteStore.createNewUnsavedNote() {
            unsavedNoteIDs.insert(newNote.id)
            selectedNoteID = newNote.id
            originalContent = ""
            editorContent = ""
            isDirty = false
            focusedField = .editor
        }
    }
    
    private func autoSelectTopMatch() {
        if searchText.isEmpty {
            // When clearing search, restore the last manual selection
            if let manualID = lastManualSelection,
               noteStore.notes.contains(where: { $0.id == manualID }) {
                selectedNoteID = manualID
            }
            previousSearchWasEmpty = true
        } else {
            // Before auto-selecting, save the current selection as manual
            // (only if search was previously empty, indicating this is the start of a search)
            if previousSearchWasEmpty, let currentID = selectedNoteID {
                lastManualSelection = currentID
            }

            // Auto-select the first match
            if let firstMatch = filteredNotes.first {
                selectedNoteID = firstMatch.id
            }

            previousSearchWasEmpty = false
        }
    }

    private func loadSelectedNote(id: UUID?) {
        guard let id = id,
              let note = noteStore.notes.first(where: { $0.id == id }) else {
            originalContent = ""
            editorContent = ""
            isDirty = false
            return
        }

        // Skip file loading for unsaved notes - file doesn't exist on disk yet
        if unsavedNoteIDs.contains(id) {
            originalContent = ""
            editorContent = ""
            isDirty = false
            return
        }

        let noteID = id
        Task {
            do {
                let content = try await loadFileAsync(url: note.url)
                await MainActor.run {
                    originalContent = content
                    editorContent = content
                    isDirty = false
                    unsavedNoteIDs.remove(noteID)
                }
            } catch {
                let errorContent = "Error loading file: \(error.localizedDescription)"
                await MainActor.run {
                    originalContent = errorContent
                    editorContent = errorContent
                    isDirty = false
                    unsavedNoteIDs.remove(noteID)
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
        let ext = AppSettings.shared.defaultExtension.rawValue
        let fileURL = folderURL.appendingPathComponent(fileName + ".\(ext)")

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
        // Don't clear selectedNoteID - let autoSelectTopMatch() handle it
        // This allows it to restore the last manual selection
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
        guard let selectedID = selectedNoteID else { return }
        guard editorContent != originalContent else { return }
        
        isDirty = true
        unsavedNoteIDs.insert(selectedID)
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
                originalContent = content
                isDirty = false
                unsavedNoteIDs.remove(id)
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
                if let noteID = noteStore.notes.first(where: { $0.url == error.fileURL })?.id {
                    unsavedNoteIDs.remove(noteID)
                }
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
    var onEscapeToSearch: () -> Void
    
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
                        Text(note.displayPath)
                            .font(.system(size: 11))
                            .italic(note.isUnsaved)
                            .foregroundColor(note.isUnsaved ? .orange : .secondary)
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
                    if press.key == .escape {
                        onEscapeToSearch()
                        return .handled
                    }
                    if press.key == .rightArrow {
                        onTabToEditor()
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
    @ObservedObject private var settings = AppSettings.shared
    var onShiftTab: (() -> Void)?
    var onEscape: (() -> Void)?

    var body: some View {
        PlainTextEditor(
            text: $content,
            fontSize: CGFloat(settings.fontSize),
            onShiftTab: onShiftTab,
            onEscape: onEscape
        )
        .focused($focusedField, equals: .editor)
    }
}

#Preview {
    ContentView(noteStore: NoteStore())
}
