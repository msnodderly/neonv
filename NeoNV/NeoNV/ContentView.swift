import SwiftUI

enum FocusedField: Hashable {
    case search
    case noteList
    case editor
}

struct SaveError: Identifiable {
    let id = UUID()
    let url: URL
    let error: Error
}

struct ContentView: View {
    @ObservedObject var noteStore: NoteStore
    @State private var searchText = ""
    @State private var selectedNoteID: UUID?
    @State private var editorContent = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var isLoadingNote = false
    @State private var lastSaveError: SaveError?
    @FocusState private var focusedField: FocusedField?
    
    var body: some View {
        VStack(spacing: 0) {
            SearchBar(
                text: $searchText,
                focusedField: _focusedField,
                onNavigateToList: navigateToList
            )
            
            Divider()
            
            if noteStore.selectedFolderURL == nil {
                EmptyStateView(onSelectFolder: noteStore.selectFolder)
            } else {
                HSplitView {
                    NoteListView(
                        notes: noteStore.notes,
                        selectedNoteID: $selectedNoteID,
                        focusedField: _focusedField,
                        isLoading: noteStore.isLoading,
                        onTabToEditor: { focusedField = .editor },
                        onShiftTabToSearch: { focusedField = .search },
                        onEnterToEditor: { focusedField = .editor }
                    )
                    .frame(minWidth: 150, idealWidth: 200, maxWidth: 350)
                    .disabled(lastSaveError != nil)
                    
                    EditorView(
                        content: $editorContent,
                        focusedField: _focusedField,
                        onShiftTab: { focusedField = .noteList },
                        onEscape: { focusedField = .noteList }
                    )
                    .frame(minWidth: 300)
                    .disabled(lastSaveError != nil)
                }
            }
        }
        .disabled(lastSaveError != nil)
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            focusedField = .search
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if noteStore.isDirty {
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
        .onChange(of: lastSaveError?.id) { _, newID in
            if newID != nil, let saveError = lastSaveError {
                showSaveErrorAlert(saveError: saveError)
            }
        }
    }
    
    private func showSaveErrorAlert(saveError: SaveError) {
        let alert = NSAlert()
        alert.messageText = "Save Failed"
        alert.informativeText = "Could not save to \(saveError.url.lastPathComponent).\n\nError: \(saveError.error.localizedDescription)"
        alert.alertStyle = .critical
        
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Save As...")
        alert.addButton(withTitle: "Copy to Clipboard")
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Discard Changes")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            handleSaveRetry()
        } else if response == .alertSecondButtonReturn {
            handleSaveAs()
        } else if response == .alertThirdButtonReturn {
            handleCopyToClipboard()
        } else if response.rawValue == NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 1 {
            handleShowInFinder()
        } else if response.rawValue == NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 2 {
            handleDiscardChanges()
        }
    }
    
    private func loadSelectedNote(id: UUID?) {
        guard let id = id,
              let note = noteStore.notes.first(where: { $0.id == id }) else {
            editorContent = ""
            noteStore.isDirty = false
            return
        }
        
        isLoadingNote = true
        Task {
            do {
                let content = try await loadFileAsync(url: note.url)
                await MainActor.run {
                    editorContent = content
                    noteStore.isDirty = false
                    isLoadingNote = false
                }
            } catch {
                await MainActor.run {
                    editorContent = "Error loading file: \(error.localizedDescription)"
                    noteStore.isDirty = false
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
        if selectedNoteID == nil, let firstNote = noteStore.notes.first {
            selectedNoteID = firstNote.id
        }
        focusedField = .noteList
    }
    
    private func scheduleAutoSave() {
        guard selectedNoteID != nil, !isLoadingNote else { return }
        noteStore.isDirty = true
        
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
                noteStore.isDirty = false
                lastSaveError = nil
            }
        } catch {
            await MainActor.run {
                lastSaveError = SaveError(url: note.url, error: error)
            }
        }
    }
    
    private func handleSaveRetry() {
        Task {
            await performSave()
        }
    }
    
    private func handleSaveAs() {
        guard let saveError = lastSaveError else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = saveError.url.lastPathComponent
        
        if panel.runModal() == .OK, let url = panel.url {
            let content = editorContent
            Task {
                do {
                    try await atomicWrite(content: content, to: url)
                    await MainActor.run {
                        noteStore.isDirty = false
                        lastSaveError = nil
                        // Ideally we should also update the note store or selection here
                        // but for now we just clear the error state
                    }
                } catch {
                    await MainActor.run {
                        lastSaveError = SaveError(url: url, error: error)
                    }
                }
            }
        }
    }
    
    private func handleCopyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(editorContent, forType: .string)
    }
    
    private func handleShowInFinder() {
        guard let saveError = lastSaveError else { return }
        NSWorkspace.shared.activateFileViewerSelecting([saveError.url])
    }
    
    private func handleDiscardChanges() {
        noteStore.isDirty = false
        lastSaveError = nil
        loadSelectedNote(id: selectedNoteID)
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
    var onNavigateToList: () -> Void
    
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
    ContentView(noteStore: NoteStore())
}
