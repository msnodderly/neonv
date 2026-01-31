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
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var showPreview = false
    @State private var noteToDelete: NoteFile?
    @State private var externalConflict: ExternalConflict?
    @State private var externalToastMessage: String?
    @State private var selectedNoteURL: URL?
    @State private var showFindBar = false
    @State private var showHelp = false
    @State private var showKeyboardShortcuts = false
    @FocusState private var focusedField: FocusedField?

    struct ExternalConflict: Identifiable {
        let id = UUID()
        let url: URL
        let externalContent: String
    }

    struct SaveError: Identifiable {
        let id = UUID()
        let fileURL: URL
        let error: Error
        let content: String
    }

    private var filteredNotes: [NoteFile] {
        let query = debouncedSearchText
        let baseNotes = query.isEmpty ? noteStore.notes : noteStore.notes.filter { $0.matches(query: query) }

        if unsavedNoteIDs.isEmpty {
            return baseNotes
        }

        return baseNotes.map { note in
            guard unsavedNoteIDs.contains(note.id) else { return note }
            var updatedNote = note
            updatedNote.isUnsaved = true
            return updatedNote
        }
    }

    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            if !settings.isSearchFieldHidden {
                SearchBar(
                    text: $searchText,
                    focusedField: _focusedField,
                    matchCount: filteredNotes.count,
                    onNavigateToList: navigateToList,
                    onNavigateToEditor: { focusedField = .editor },
                    onCreateNote: createNewNote,
                    onClearSearch: clearSearch
                )

                CollapsibleSearchDivider(
                    isSearchHidden: $settings.isSearchFieldHidden,
                    onHide: { focusedField = .editor }
                )
            } else {
                ExpandableSearchDivider(
                    isSearchHidden: $settings.isSearchFieldHidden,
                    onExpand: { focusedField = .search }
                )
            }

            if noteStore.selectedFolderURL == nil {
                EmptyStateView(onSelectFolder: noteStore.selectFolder)
            } else if settings.layoutMode == .horizontal {
                horizontalLayout
            } else {
                verticalLayout
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
            if newText.isEmpty {
                // Immediate update when clearing search
                searchDebounceTask?.cancel()
                debouncedSearchText = ""
                autoSelectTopMatch()
            } else {
                searchDebounceTask?.cancel()
                searchDebounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(50))
                    guard !Task.isCancelled else { return }
                    debouncedSearchText = newText
                    autoSelectTopMatch()
                }
            }
        }
        .onChange(of: noteStore.lastExternalChange) { _, change in
            if let change = change {
                handleExternalChange(change)
            }
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
        .alert(item: $externalConflict) { conflict in
            Alert(
                title: Text("File Changed Externally"),
                message: Text("\(conflict.url.lastPathComponent) was modified outside neonv.\n\nYou have unsaved changes. What would you like to do?"),
                primaryButton: .default(Text("Keep Mine")) {
                    // Keep current editor content, mark dirty to re-save
                    isDirty = true
                    scheduleAutoSave()
                },
                secondaryButton: .destructive(Text("Use External")) {
                    editorContent = conflict.externalContent
                    originalContent = conflict.externalContent
                    isDirty = false
                }
            )
        }
        .overlay(alignment: .bottom) {
            if let message = externalToastMessage {
                Text(message)
                    .font(.system(size: 12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation { externalToastMessage = nil }
                        }
                    }
            }
        }
        .disabled(saveError != nil || externalConflict != nil)
        .alert("Delete Note", isPresented: Binding(
            get: { noteToDelete != nil },
            set: { if !$0 { noteToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                noteToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let note = noteToDelete {
                    deleteNote(note)
                }
            }
        } message: {
            if let note = noteToDelete {
                Text("Are you sure you want to delete \"\(note.displayTitle)\"? This action cannot be undone.")
            }
        }
        .modifier(NotificationHandlers(
            onFocusSearch: {
                if settings.isSearchFieldHidden {
                    settings.isSearchFieldHidden = false
                }
                focusSearch()
            },
            onCreateNewNote: createNewNoteFromShortcut,
            onTogglePreview: togglePreview,
            onFindInNote: {
                guard selectedNoteID != nil else { return }
                if showPreview { showPreview = false }
                focusedField = .editor
                showFindBar = true
            },
            onDeleteNote: {
                guard focusedField == .noteList else { return }
                if let id = selectedNoteID,
                   let note = noteStore.notes.first(where: { $0.id == id }) {
                    noteToDelete = note
                }
            },
            onShowInFinder: showInFinder,
            onShowHelp: { showHelp = true },
            onShowKeyboardShortcuts: { showKeyboardShortcuts = true },
            onOpenInExternalEditor: openInExternalEditor,
            onToggleSearchField: toggleSearchField,
            onToggleFileList: toggleFileList,
            onToggleLayout: toggleLayout
        ))
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
        .sheet(isPresented: $showKeyboardShortcuts) {
            KeyboardShortcutsView()
        }
    }

    @ViewBuilder
    private var previewPane: some View {
        if selectedNoteURL?.pathExtension.lowercased() == "org" {
            OrgPreviewView(
                content: editorContent,
                fontSize: CGFloat(AppSettings.shared.fontSize),
                onShiftTab: { focusedField = .noteList },
                onTypeToEdit: { switchToEditor() }
            )
            .focused($focusedField, equals: .preview)
            .frame(minWidth: 300)
        } else {
            MarkdownPreviewView(
                content: editorContent,
                fontSize: CGFloat(AppSettings.shared.fontSize),
                onShiftTab: { focusedField = .noteList },
                onTypeToEdit: { switchToEditor() }
            )
            .focused($focusedField, equals: .preview)
            .frame(minWidth: 300)
        }
    }

    @ViewBuilder
    private var verticalLayout: some View {
        HSplitView {
            if !settings.isFileListHidden {
                noteListPane
                    .frame(minWidth: 150, idealWidth: 200, maxWidth: 350)
            }
            editorOrPreviewPane
        }
    }

    @ViewBuilder
    private var horizontalLayout: some View {
        VSplitView {
            if !settings.isFileListHidden {
                HorizontalNoteListView(
                    notes: filteredNotes,
                    selectedNoteID: $selectedNoteID,
                    focusedField: _focusedField,
                    isLoading: noteStore.isLoading,
                    searchText: debouncedSearchText,
                    onTabToEditor: { focusedField = .editor },
                    onShiftTabToSearch: { focusedField = .search },
                    onEnterToEditor: { focusedField = .editor },
                    onEscapeToSearch: { focusedField = .search },
                    onUpArrowToSearch: { focusedField = .search },
                    onDeleteNote: { note in noteToDelete = note },
                    onShowInFinder: { note in
                        NSWorkspace.shared.activateFileViewerSelecting([note.url])
                    }
                )
                .frame(minHeight: 80, idealHeight: 150, maxHeight: 300)
            }
            editorOrPreviewPane
        }
    }

    @ViewBuilder
    private var noteListPane: some View {
        NoteListView(
            notes: filteredNotes,
            selectedNoteID: $selectedNoteID,
            focusedField: _focusedField,
            isLoading: noteStore.isLoading,
            searchText: debouncedSearchText,
            onTabToEditor: { focusedField = .editor },
            onShiftTabToSearch: { focusedField = .search },
            onEnterToEditor: { focusedField = .editor },
            onEscapeToSearch: { focusedField = .search },
            onUpArrowToSearch: { focusedField = .search },
            onDeleteNote: { note in noteToDelete = note },
            onShowInFinder: { note in
                NSWorkspace.shared.activateFileViewerSelecting([note.url])
            }
        )
    }

    @ViewBuilder
    private var editorOrPreviewPane: some View {
        if filteredNotes.isEmpty {
            ContentEmptyStateView(
                hasNotes: !noteStore.notes.isEmpty,
                searchText: searchText
            )
            .frame(minWidth: 300)
        } else if showPreview {
            previewPane
        } else {
            EditorView(
                content: $editorContent,
                showFindBar: $showFindBar,
                focusedField: _focusedField,
                searchText: debouncedSearchText,
                onShiftTab: { focusedField = settings.isFileListHidden ? .search : .noteList },
                onEscape: { focusedField = settings.isFileListHidden ? .search : .noteList }
            )
            .frame(minWidth: 300)
        }
    }

    private func focusSearch() {
        focusedField = .search
    }

    private func deleteNote(_ note: NoteFile) {
        let notes = filteredNotes
        let currentIndex = notes.firstIndex(where: { $0.id == note.id })

        do {
            try noteStore.deleteNote(id: note.id)
            unsavedNoteIDs.remove(note.id)

            // Select adjacent note
            if let idx = currentIndex {
                let remaining = filteredNotes
                if !remaining.isEmpty {
                    let newIndex = min(idx, remaining.count - 1)
                    selectedNoteID = remaining[newIndex].id
                } else {
                    selectedNoteID = nil
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to Delete Note"
            alert.informativeText = "Could not delete \"\(note.displayTitle)\":\n\n\(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }

        noteToDelete = nil
    }

    private func togglePreview() {
        showPreview.toggle()
        // Only switch focus if currently in editor or preview pane
        // If focused on list or search, keep focus there
        if focusedField == .editor || focusedField == .preview {
            if showPreview {
                focusedField = .preview
            } else {
                focusedField = .editor
            }
        }
    }

    private func toggleSearchField() {
        settings.isSearchFieldHidden.toggle()
        if settings.isSearchFieldHidden {
            if focusedField == .search {
                focusedField = .editor
            }
        } else {
            focusedField = .search
        }
    }

    private func toggleFileList() {
        withAnimation(.easeInOut(duration: 0.2)) {
            settings.isFileListHidden.toggle()
        }
        if settings.isFileListHidden {
            if focusedField == .noteList {
                focusedField = .editor
            }
        } else {
            focusedField = .noteList
        }
    }

    private func toggleLayout() {
        withAnimation(.easeInOut(duration: 0.2)) {
            settings.layoutMode = settings.layoutMode == .vertical ? .horizontal : .vertical
        }
        // Focus search after layout switch — the list/editor views are being
        // torn down and rebuilt so they can't reliably accept focus immediately.
        if settings.isSearchFieldHidden {
            settings.isSearchFieldHidden = false
        }
        focusedField = .search
    }

    private func switchToEditor() {
        showPreview = false
        focusedField = .editor
    }

    private func openInExternalEditor() {
        guard let url = selectedNoteURL else { return }

        let settings = AppSettings.shared
        if let editorPath = settings.externalEditorPath {
            let editorURL = URL(fileURLWithPath: editorPath)
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: editorURL, configuration: config) { _, error in
                if let error = error {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Failed to Open External Editor"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func showInFinder() {
        guard let url = selectedNoteURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func handleExternalChange(_ change: ExternalChangeEvent) {
        switch change.kind {
        case .modified:
            guard let selectedID = selectedNoteID,
                  let selectedNote = noteStore.notes.first(where: { $0.id == selectedID }),
                  selectedNote.url == change.url else { return }

            Task {
                guard let newContent = try? await loadFileAsync(url: change.url) else { return }
                await MainActor.run {
                    if isDirty {
                        saveTask?.cancel()
                        externalConflict = ExternalConflict(url: change.url, externalContent: newContent)
                    } else {
                        editorContent = newContent
                        originalContent = newContent
                        withAnimation { externalToastMessage = "Reloaded — file changed externally" }
                    }
                }
            }
        case .deleted:
            guard selectedNoteURL == change.url else { return }
            let name = change.url.lastPathComponent
            editorContent = ""
            originalContent = ""
            isDirty = false
            selectedNoteID = nil
            selectedNoteURL = nil
            withAnimation { externalToastMessage = "\(name) was deleted externally" }
        }
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
            selectedNoteURL = nil
            originalContent = ""
            editorContent = ""
            isDirty = false
            return
        }
        selectedNoteURL = note.url

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
                noteStore.markAsSavedLocally(fileURL)
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
        guard externalConflict == nil else { return }
        guard let id = selectedNoteID,
              let note = noteStore.notes.first(where: { $0.id == id }) else {
            return
        }

        let content = editorContent

        do {
            noteStore.markAsSavedLocally(note.url)
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

struct ContentEmptyStateView: View {
    var hasNotes: Bool
    var searchText: String

    var body: some View {
        VStack(spacing: 12) {
            if !hasNotes {
                Image(systemName: "note.text")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
                Text("No notes yet")
                    .font(.headline)
                Text("Start typing to create one.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
                Text("No matches")
                    .font(.headline)
                Text("Press Enter to create \"\(searchText)\"")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            
            Text("Select a folder to get started")
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
    var onNavigateToEditor: () -> Void
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
                    if matchCount == 1 {
                        onNavigateToEditor()
                    } else if matchCount > 1 {
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

struct CollapsibleSearchDivider: View {
    @Binding var isSearchHidden: Bool
    var onHide: () -> Void
    @State private var isHovering = false
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(isHovering ? Color.accentColor.opacity(0.3) : Color(NSColor.separatorColor))
            .frame(height: isHovering ? 4 : 1)
            .contentShape(Rectangle().inset(by: -4))
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation.height
                    }
                    .onEnded { value in
                        if value.translation.height < -20 {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSearchHidden = true
                            }
                            onHide()
                        }
                    }
            )
            .help("Drag up to hide search field")
    }
}

struct ExpandableSearchDivider: View {
    @Binding var isSearchHidden: Bool
    var onExpand: () -> Void
    @State private var isHovering = false
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(isHovering ? Color.accentColor.opacity(0.3) : Color(NSColor.separatorColor))
            .frame(height: isHovering ? 4 : 1)
            .contentShape(Rectangle().inset(by: -4))
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation.height
                    }
                    .onEnded { value in
                        if value.translation.height > 10 {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSearchHidden = false
                            }
                            onExpand()
                        }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearchHidden = false
                }
                onExpand()
            }
            .help("Drag down or double-click to show search field (⌘L)")
    }
}

struct NoteListView: View {
    var notes: [NoteFile]
    @Binding var selectedNoteID: UUID?
    @FocusState var focusedField: FocusedField?
    var isLoading: Bool
    var searchText: String
    var onTabToEditor: () -> Void
    var onShiftTabToSearch: () -> Void
    var onEnterToEditor: () -> Void
    var onEscapeToSearch: () -> Void
    var onUpArrowToSearch: () -> Void
    var onDeleteNote: ((NoteFile) -> Void)?
    var onShowInFinder: ((NoteFile) -> Void)?

    @ObservedObject private var settings = AppSettings.shared

    private var searchTerms: [String] {
        guard settings.searchHighlightingEnabled, !searchText.isEmpty else { return [] }
        return [searchText]
    }

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
                        HighlightedText(
                            note.displayTitle,
                            highlighting: searchTerms,
                            font: .system(size: 13, weight: .medium),
                            color: .primary
                        )
                        .lineLimit(1)

                        if note.isUnsaved {
                            Text(note.displayPath)
                                .font(.system(size: 11))
                                .italic()
                                .foregroundColor(.orange)
                        } else {
                            HighlightedText(
                                note.displayPath,
                                highlighting: searchTerms,
                                font: .system(size: 11),
                                color: .secondary
                            )
                        }
                    }
                    .tag(note.id)
                    .contextMenu {
                        if let onShowInFinder = onShowInFinder {
                            Button("Show in Finder") {
                                onShowInFinder(note)
                            }
                        }
                        if let onDeleteNote = onDeleteNote {
                            Button("Delete", role: .destructive) {
                                onDeleteNote(note)
                            }
                        }
                    }
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
                    if press.key == .upArrow {
                        if let firstNote = notes.first, selectedNoteID == firstNote.id {
                            onUpArrowToSearch()
                            return .handled
                        }
                    }
                    return .ignored
                }
            }
        }
    }
}

struct EditorView: View {
    @Binding var content: String
    @Binding var showFindBar: Bool
    @FocusState var focusedField: FocusedField?
    @ObservedObject private var settings = AppSettings.shared
    var searchText: String
    var onShiftTab: (() -> Void)?
    var onEscape: (() -> Void)?

    private var searchTerms: [String] {
        guard settings.searchHighlightingEnabled, !searchText.isEmpty else { return [] }
        return [searchText]
    }

    var body: some View {
        PlainTextEditor(
            text: $content,
            fontSize: CGFloat(settings.fontSize),
            showFindBar: showFindBar,
            searchTerms: searchTerms,
            onShiftTab: onShiftTab,
            onEscape: onEscape
        )
        .focused($focusedField, equals: .editor)
        .onChange(of: showFindBar) { _, newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showFindBar = false
                }
            }
        }
    }
}

struct NotificationHandlers: ViewModifier {
    let onFocusSearch: () -> Void
    let onCreateNewNote: () -> Void
    let onTogglePreview: () -> Void
    let onFindInNote: () -> Void
    let onDeleteNote: () -> Void
    let onShowInFinder: () -> Void
    let onShowHelp: () -> Void
    let onShowKeyboardShortcuts: () -> Void
    let onOpenInExternalEditor: () -> Void
    let onToggleSearchField: () -> Void
    let onToggleFileList: () -> Void
    let onToggleLayout: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
                onFocusSearch()
            }
            .onReceive(NotificationCenter.default.publisher(for: .createNewNote)) { _ in
                onCreateNewNote()
            }
            .onReceive(NotificationCenter.default.publisher(for: .togglePreview)) { _ in
                onTogglePreview()
            }
            .onReceive(NotificationCenter.default.publisher(for: .findInNote)) { _ in
                onFindInNote()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deleteNote)) { _ in
                onDeleteNote()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showInFinder)) { _ in
                onShowInFinder()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showHelp)) { _ in
                onShowHelp()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showKeyboardShortcuts)) { _ in
                onShowKeyboardShortcuts()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openInExternalEditor)) { _ in
                onOpenInExternalEditor()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSearchField)) { _ in
                onToggleSearchField()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleFileList)) { _ in
                onToggleFileList()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleLayout)) { _ in
                onToggleLayout()
            }
    }
}

#Preview {
    ContentView(noteStore: NoteStore())
}
