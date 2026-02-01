import SwiftUI

enum FocusedField: Hashable {
    case search
    case noteList
    case editor
    case preview
}

struct ContentView: View {
    @ObservedObject var noteStore: NoteStore
    @State var searchText = ""
    @State var selectedNoteID: UUID?
    @State var lastManualSelection: UUID?
    @State var previousSearchWasEmpty = true
    @State var editorContent = ""
    @State var originalContent = ""
    @State var isDirty = false
    @State var saveTask: Task<Void, Never>?
    @State var saveError: SaveError?
    @State var unsavedNoteIDs: Set<UUID> = []
    @State var debouncedSearchText = ""
    @State var searchDebounceTask: Task<Void, Never>?
    @State var showPreview = false
    @State var noteToDelete: NoteFile?
    @State var externalConflict: ExternalConflict?
    @State var externalToastMessage: String?
    @State var selectedNoteURL: URL?
    @State var showFindBar = false
    @State var showHelp = false
    @State var cursorPosition = 0
    @State var showKeyboardShortcuts = false
    @FocusState var focusedField: FocusedField?

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

    var filteredNotes: [NoteFile] {
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

    @ObservedObject var settings = AppSettings.shared

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
                focusedField = .search
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

    // MARK: - Layout Views

    @ViewBuilder
    var previewPane: some View {
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
    var verticalLayout: some View {
        HSplitView {
            if !settings.isFileListHidden {
                noteListPane
                    .frame(minWidth: 150, idealWidth: 200, maxWidth: 350)
            }
            editorOrPreviewPane
        }
    }

    @ViewBuilder
    var horizontalLayout: some View {
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
    var noteListPane: some View {
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
    var editorOrPreviewPane: some View {
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
                cursorPosition: $cursorPosition,
                focusedField: _focusedField,
                searchText: debouncedSearchText,
                onShiftTab: { focusedField = settings.isFileListHidden ? .search : .noteList },
                onEscape: { focusedField = settings.isFileListHidden ? .search : .noteList }
            )
            .frame(minWidth: 300)
        }
    }
}

#Preview {
    ContentView(noteStore: NoteStore())
}
