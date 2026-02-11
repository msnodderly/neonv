// swiftlint:disable file_length
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
    @State private var loadError: LoadError?
    @State private var unsavedNoteIDs: Set<UUID> = []
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var showPreview = false
    @State private var noteToDelete: NoteFile?
    @State private var noteToRename: NoteFile?
    @State private var renameText: String = ""
    @State private var renameError: String?
    @State private var externalConflict: ExternalConflict?
    @State private var externalToastMessage: String?
    @State private var selectedNoteURL: URL?
    @State private var isReadOnly = false
    @State private var showFindBar = false
    @State private var showHelp = false
    @State private var cursorPosition = 0
    @State private var cursorPositionMap: [UUID: Int] = [:]
    @State private var pendingCursorAtEnd = false
    @State private var showKeyboardShortcuts = false
    @State private var noteToTag: NoteFile?
    @State private var tagText: String = ""
    @State private var editorScrollFraction: CGFloat = 0
    @State private var previewScrollFraction: CGFloat = 0
    @State private var restoreEditorScrollFraction: CGFloat?
    @StateObject private var navHistory = NavigationHistory()
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

    struct LoadError: Identifiable {
        let id = UUID()
        let fileURL: URL
        let error: Error
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
                    onNavigateToEditor: focusEditor,
                    onCreateNote: createNewNote,
                    onClearSearch: clearSearch
                )

                CollapsibleSearchDivider(isSearchHidden: $settings.isSearchFieldHidden,
                    onHide: { focusedField = .editor })
            } else {
                ExpandableSearchDivider(isSearchHidden: $settings.isSearchFieldHidden,
                    onExpand: { focusedField = .search })
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
                if isReadOnly {
                    Text("Read Only").font(.system(size: 11)).foregroundColor(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15)).cornerRadius(4)
                } else if isDirty {
                    Circle().fill(.orange).frame(width: 8, height: 8).help("Unsaved changes")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button(action: togglePreview) {
                    Label(showPreview ? "Hide preview" : "Show preview",
                          systemImage: showPreview ? "eye.fill" : "eye")
                }
                .labelStyle(.iconOnly)
                .help(showPreview ? "Hide preview (⌘P)" : "Show preview (⌘P)")
            }
            ToolbarItem(placement: .automatic) {
                Button(action: noteStore.selectFolder) {
                    Label("Select notes folder", systemImage: "folder")
                }
                .labelStyle(.iconOnly)
                .help("Select notes folder")
            }
        }
        .onChange(of: selectedNoteID) { _, newID in
            if let newID = newID {
                navHistory.push(newID)
            }
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
        .alert("Move to Trash", isPresented: Binding(
            get: { noteToDelete != nil },
            set: { if !$0 { noteToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                noteToDelete = nil
            }
            Button("Move to Trash", role: .destructive) {
                if let note = noteToDelete {
                    deleteNote(note)
                }
            }
        } message: {
            if let note = noteToDelete {
                Text("Are you sure you want to move \"\(note.displayTitle)\" to the Trash?")
            }
        }
        .alert("Rename Note", isPresented: Binding(
            get: { noteToRename != nil },
            set: { if !$0 { noteToRename = nil; renameError = nil } }
        )) {
            TextField("New name", text: $renameText)
            Button("Cancel", role: .cancel) {
                noteToRename = nil
                renameError = nil
            }
            Button("Rename") {
                if let note = noteToRename {
                    renameNote(note, to: renameText)
                }
            }
        } message: {
            if let error = renameError {
                Text(error)
            } else if let note = noteToRename {
                Text("The extension \".\(note.url.pathExtension)\" will be added automatically.")
            }
        }
        .alert("Add Tags", isPresented: Binding(
            get: { noteToTag != nil },
            set: { if !$0 { noteToTag = nil; tagText = "" } }
        )) {
            TextField("Tags (comma-separated)", text: $tagText)
            Button("Cancel", role: .cancel) {
                noteToTag = nil
                tagText = ""
            }
            Button("Save") {
                if let note = noteToTag {
                    addTagsToNote(note, tagString: tagText)
                }
            }
        } message: {
            if let note = noteToTag {
                let isOrgFile = note.url.pathExtension.lowercased() == "org"
                if note.tags.isEmpty {
                    if isOrgFile {
                        Text("Add tags to \"\(note.displayTitle)\"\n\nEnter tags separated by commas.\nWill be saved as #+FILETAGS: :tag1:tag2:")
                    } else {
                        Text("Add tags to \"\(note.displayTitle)\"\n\nEnter tags separated by commas (e.g., work, important, todo)")
                    }
                } else {
                    Text("Current tags: \(note.tags.joined(separator: ", "))\n\nEnter tags separated by commas")
                }
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
            onToggleLayout: toggleLayout,
            onAddTag: {
                guard let id = selectedNoteID,
                      let note = noteStore.notes.first(where: { $0.id == id }),
                      !note.isUnsaved else { return }
                tagText = note.tags.joined(separator: ", ")
                noteToTag = note
            },
            onNavigateBack: {
                if let target = navHistory.goBack(current: selectedNoteID) {
                    selectedNoteID = target
                }
            },
            onNavigateForward: {
                if let target = navHistory.goForward(current: selectedNoteID) {
                    selectedNoteID = target
                }
            }
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
                initialScrollFraction: editorScrollFraction,
                scrollFraction: $previewScrollFraction,
                onShiftTab: { focusedField = .noteList },
                onTypeToEdit: { switchToEditor() }
            )
            .focused($focusedField, equals: .preview)
            .frame(minWidth: 300)
        } else {
            MarkdownPreviewView(
                content: editorContent,
                fontSize: CGFloat(AppSettings.shared.fontSize),
                initialScrollFraction: editorScrollFraction,
                scrollFraction: $previewScrollFraction,
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
                    onTabToEditor: focusEditor,
                    onShiftTabToSearch: focusSearch,
                    onEnterToEditor: focusEditor,
                    onEscapeToSearch: { focusedField = .search },
                    onUpArrowToSearch: { focusedField = .search },
                    onDeleteNote: { note in noteToDelete = note },
                    onShowInFinder: { note in
                        NSWorkspace.shared.activateFileViewerSelecting([note.url])
                    },
                    onRenameNote: { note in
                        renameText = note.url.deletingPathExtension().lastPathComponent
                        noteToRename = note
                    },
                    onAddTag: { note in
                        tagText = note.tags.joined(separator: ", ")
                        noteToTag = note
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
            onTabToEditor: focusEditor,
            onShiftTabToSearch: focusSearch,
            onEnterToEditor: focusEditor,
            onEscapeToSearch: { focusedField = .search },
            onUpArrowToSearch: { focusedField = .search },
            onDeleteNote: { note in noteToDelete = note },
            onShowInFinder: { note in
                NSWorkspace.shared.activateFileViewerSelecting([note.url])
            },
            onRenameNote: { note in
                renameText = note.url.deletingPathExtension().lastPathComponent
                noteToRename = note
            },
            onAddTag: { note in
                tagText = note.tags.joined(separator: ", ")
                noteToTag = note
            }
        )
    }

    @ViewBuilder
    private var editorOrPreviewPane: some View {
        if let error = loadError {
            FileLoadErrorView(fileURL: error.fileURL, error: error.error,
                onShowInFinder: { NSWorkspace.shared.activateFileViewerSelecting([error.fileURL]) })
                .frame(minWidth: 300)
        } else if filteredNotes.isEmpty {
            ContentEmptyStateView(hasNotes: !noteStore.notes.isEmpty, searchText: searchText)
                .frame(minWidth: 300)
        } else {
            ZStack {
                EditorView(content: $editorContent, showFindBar: $showFindBar,
                    cursorPosition: $cursorPosition,
                    scrollFraction: $editorScrollFraction,
                    restoreScrollFraction: restoreEditorScrollFraction,
                    focusedField: _focusedField,
                    searchText: debouncedSearchText, isEditable: !isReadOnly,
                    isHiddenFromFocus: showPreview,
                    onShiftTab: navigateToList,
                    onEscape: navigateToList)
                    .opacity(showPreview ? 0 : 1)
                    .allowsHitTesting(!showPreview)
                    .accessibilityHidden(showPreview)

                if showPreview {
                    previewPane
                }
            }
            .frame(minWidth: 300)
        }
    }

    private func focusSearch() {
        if settings.isSearchFieldHidden {
            settings.isSearchFieldHidden = false
        }
        NSApp.keyWindow?.makeFirstResponder(nil)
        focusedField = .search
    }

    private func focusEditor() {
        if showPreview {
            showPreview = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .editor
            }
        } else {
            focusedField = .editor
        }
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
            alert.messageText = "Failed to Move to Trash"
            alert.informativeText = "Could not move \"\(note.displayTitle)\" to the Trash:\n\n\(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }

        noteToDelete = nil
    }

    private func renameNote(_ note: NoteFile, to newName: String) {
        // Cancel pending autosave to prevent writes to the old URL after rename.
        saveTask?.cancel()
        saveTask = nil
        // Flush unsaved changes to disk before moving the file.
        if isDirty, selectedNoteID == note.id {
            let content = editorContent
            noteStore.markAsSavedLocally(note.url, content: content)
            do {
                try content.data(using: .utf8)!.write(to: note.url, options: .atomic)
            } catch {
                renameError = "Failed to save before rename: \(error.localizedDescription)"
                return
            }
            originalContent = content
            isDirty = false
            unsavedNoteIDs.remove(note.id)
            AppDelegate.shared.hasUnsavedChanges = false
        }

        do {
            let renamed = try noteStore.renameNote(id: note.id, newName: newName)
            selectedNoteID = renamed.id
            selectedNoteURL = renamed.url
            noteToRename = nil
            renameError = nil
        } catch {
            renameError = error.localizedDescription
        }
    }

    private func addTagsToNote(_ note: NoteFile, tagString: String) {
        guard !note.isUnsaved else {
            noteToTag = nil
            tagText = ""
            return
        }

        let isOrgFile = note.url.pathExtension.lowercased() == "org"

        Task {
            do {
                // Read current file content
                let currentContent = try String(contentsOf: note.url, encoding: .utf8)
                var lines = currentContent.components(separatedBy: .newlines)

                // Parse new tags (support both comma and colon separators for input)
                var inputTags: [String]
                if tagString.contains(":") && !tagString.contains(",") {
                    // Org-mode style input: :tag1:tag2:tag3:
                    inputTags = tagString.components(separatedBy: ":")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                } else {
                    // Standard comma-separated input
                    inputTags = tagString.components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }

                // For non-org files, ensure tags have # prefix
                if !isOrgFile {
                    inputTags = inputTags.map { tag in
                        tag.hasPrefix("#") ? tag : "#\(tag)"
                    }
                }

                // Use the input tags exactly (replacing existing tags, not merging)
                // This allows users to remove or modify tags by editing the text field
                let finalTags = Array(Set(inputTags)).sorted()

                // Handle empty tags case: remove existing tag line from file
                if finalTags.isEmpty {
                    // Find and remove existing tag line
                    for (index, line) in lines.enumerated() {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if isOrgFile {
                            if trimmed.uppercased().hasPrefix("#+FILETAGS:") {
                                lines.remove(at: index)
                                break
                            }
                        } else {
                            if trimmed.lowercased().hasPrefix("tags:") || trimmed.lowercased().hasPrefix("tag:") {
                                lines.remove(at: index)
                                // Also remove following blank line if present
                                if index < lines.count && lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                                    lines.remove(at: index)
                                }
                                break
                            }
                        }
                    }
                } else {
                    // Format tag line based on file type
                    let tagLine: String
                    if isOrgFile {
                        // Org-mode format: #+FILETAGS: :tag1:tag2:tag3:
                        tagLine = "#+FILETAGS: :\(finalTags.joined(separator: ":")):"
                    } else {
                        // Standard format: Tags: #tag1, #tag2, #tag3
                        tagLine = "Tags: \(finalTags.joined(separator: ", "))"
                    }

                    // Find and replace existing tag line, or add at the beginning
                    var foundTagLine = false
                    for (index, line) in lines.enumerated() {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if isOrgFile {
                            // Look for #+FILETAGS: in org files
                            if trimmed.uppercased().hasPrefix("#+FILETAGS:") {
                                lines[index] = tagLine
                                foundTagLine = true
                                break
                            }
                        } else {
                            // Look for Tags: in other files
                            if trimmed.lowercased().hasPrefix("tags:") || trimmed.lowercased().hasPrefix("tag:") {
                                lines[index] = tagLine
                                foundTagLine = true
                                break
                            }
                        }
                    }

                    if !foundTagLine {
                        if isOrgFile {
                            // For org files, add after any existing #+KEY: metadata at the top
                            var insertIndex = 0
                            for (index, line) in lines.enumerated() {
                                let trimmed = line.trimmingCharacters(in: .whitespaces)
                                if trimmed.hasPrefix("#+") {
                                    insertIndex = index + 1
                                } else if !trimmed.isEmpty {
                                    break
                                }
                            }
                            lines.insert(tagLine, at: insertIndex)
                        } else {
                            // Add at the beginning for other files
                            lines.insert(tagLine, at: 0)
                            lines.insert("", at: 1) // Add blank line after tags
                        }
                    }
                }

                let newContent = lines.joined(separator: "\n")

                // Save the file
                noteStore.markAsSavedLocally(note.url, content: newContent)
                try await atomicWrite(content: newContent, to: note.url)

                await MainActor.run {
                    // Update editor if this is the currently selected note
                    if selectedNoteID == note.id {
                        editorContent = newContent
                        originalContent = newContent
                        isDirty = false
                    }
                    noteToTag = nil
                    tagText = ""
                }
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Failed to Add Tags"
                    alert.informativeText = "Could not add tags to \"\(note.displayTitle)\":\n\n\(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    noteToTag = nil
                    tagText = ""
                }
            }
        }
    }

    private func togglePreview() {
        let wasFocusedInEditorOrPreview = (focusedField == .editor || focusedField == .preview)
        if showPreview { restoreEditorScrollFraction = previewScrollFraction }
        showPreview.toggle()
        if wasFocusedInEditorOrPreview {
            let target: FocusedField = showPreview ? .preview : .editor
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = target
                // Clear restore trigger after it's been applied
                if !showPreview { restoreEditorScrollFraction = nil }
            }
        } else if !showPreview {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { restoreEditorScrollFraction = nil }
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
        restoreEditorScrollFraction = previewScrollFraction
        showPreview = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedField = .editor
            restoreEditorScrollFraction = nil
        }
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

            // Only auto-select when the user is typing in the search field.
            // If the list has focus, the user is navigating manually — don't override.
            if focusedField != .noteList, let firstMatch = filteredNotes.first {
                selectedNoteID = firstMatch.id
            }

            previousSearchWasEmpty = false
        }
    }

    private func loadSelectedNote(id: UUID?) {
        // Save cursor position for the note we're leaving
        if let previousID = selectedNoteID {
            cursorPositionMap[previousID] = cursorPosition
        }
        // Reset scroll fractions when switching notes
        editorScrollFraction = 0
        previewScrollFraction = 0
        if isDirty, let previousID = selectedNoteID {
            saveTask?.cancel()
            let content = editorContent
            Task { await performSave(noteID: previousID, content: content) }
        }
        guard let id = id,
              let note = noteStore.notes.first(where: { $0.id == id }) else {
            selectedNoteURL = nil
            originalContent = ""
            editorContent = ""
            cursorPosition = 0
            isDirty = false
            isReadOnly = false
            loadError = nil
            return
        }
        selectedNoteURL = note.url
        isReadOnly = note.isReadOnly
        // Skip file loading for unsaved notes - file doesn't exist on disk yet
        if unsavedNoteIDs.contains(id) {
            originalContent = ""
            editorContent = ""
            cursorPosition = cursorPositionMap[id] ?? 0
            isDirty = false
            loadError = nil
            return
        }
        let noteID = id
        Task {
            do {
                let content = try await loadFileAsync(url: note.url)
                await MainActor.run {
                    originalContent = content
                    editorContent = content
                    if pendingCursorAtEnd {
                        cursorPosition = content.count
                        pendingCursorAtEnd = false
                    } else {
                        let saved = cursorPositionMap[noteID] ?? 0
                        cursorPosition = min(saved, content.count)
                    }
                    isDirty = false
                    unsavedNoteIDs.remove(noteID)
                    loadError = nil
                }
            } catch {
                await MainActor.run {
                    loadError = LoadError(fileURL: note.url, error: error)
                    originalContent = ""
                    editorContent = ""
                    cursorPosition = 0
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
        if settings.isFileListHidden { settings.isFileListHidden = false }
        if selectedNoteID == nil, let firstNote = filteredNotes.first { selectedNoteID = firstNote.id }
        NSApp.keyWindow?.makeFirstResponder(nil)
        focusedField = .noteList
    }

    private func createNewNote() {
        guard let folderURL = noteStore.selectedFolderURL, !searchText.isEmpty else {
            return
        }

        let parts = sanitizePathComponents(searchText)
        guard !parts.isEmpty else { return }

        let directoryParts = parts.dropLast()
        let baseName = parts.last!

        var dirURL = folderURL
        for part in directoryParts {
            dirURL = dirURL.appendingPathComponent(part, isDirectory: true)
        }

        let fileName: String
        if hasValidExtension(baseName) {
            fileName = baseName
        } else {
            let ext = AppSettings.shared.defaultExtension.rawValue
            fileName = "\(baseName).\(ext)"
        }
        let fileURL = dirURL.appendingPathComponent(fileName)
        let initialContent = searchText + "\n\n"

        // If the file already exists, open it instead of overwriting
        if let existingNote = noteStore.notes.first(where: { $0.url == fileURL }) {
            searchText = ""
            selectedNoteID = existingNote.id
            focusedField = .editor
            return
        }

        Task {
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

                // Use .withoutOverwriting to prevent silently replacing existing files.
                // This also guards against a TOCTOU race where the file is created
                // between the in-memory check above and this write.
                let data = initialContent.data(using: .utf8)!
                try data.write(to: fileURL, options: .withoutOverwriting)
                noteStore.markAsSavedLocally(fileURL, content: initialContent)
                await noteStore.discoverFiles()

                await MainActor.run {
                    searchText = ""
                    if let newNote = noteStore.notes.first(where: { $0.url == fileURL }) {
                        pendingCursorAtEnd = true
                        selectedNoteID = newNote.id
                        focusedField = .editor
                    }
                }
            } catch let error as NSError
                where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                // File appeared between our check and the write — open it instead
                await noteStore.discoverFiles()
                await MainActor.run {
                    searchText = ""
                    if let note = noteStore.notes.first(where: { $0.url == fileURL }) {
                        selectedNoteID = note.id
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

    private static let validExtensions: Set<String> = ["md", "txt", "org", "markdown", "text"]

    private func sanitizePathComponent(_ name: String, preserveExtension: Bool = false) -> String {
        var baseName = name
        var extensionPart: String?

        if preserveExtension {
            let lowercased = name.lowercased()
            for ext in Self.validExtensions where lowercased.hasSuffix(".\(ext)") {
                let extWithDot = ".\(ext)"
                baseName = String(name.dropLast(extWithDot.count))
                extensionPart = ext
                break
            }
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

        if let ext = extensionPart {
            sanitized += ".\(ext)"
        }

        return sanitized
    }

    private func sanitizePathComponents(_ input: String) -> [String] {
        let normalized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")

        let rawParts = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        var parts: [String] = []
        for (index, part) in rawParts.enumerated() {
            if part == "." || part == ".." { continue }
            let isLastPart = index == rawParts.count - 1
            let sanitized = sanitizePathComponent(part, preserveExtension: isLastPart)
            if !sanitized.isEmpty { parts.append(sanitized) }
        }
        return parts
    }

    private func hasValidExtension(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return Self.validExtensions.contains { lowercased.hasSuffix(".\($0)") }
    }

    private func scheduleAutoSave() {
        guard loadError == nil, let selectedID = selectedNoteID else { return }
        saveTask?.cancel()
        guard editorContent != originalContent else {
            isDirty = false
            return
        }
        isDirty = true
        unsavedNoteIDs.insert(selectedID)
        AppDelegate.shared.hasUnsavedChanges = true
        let (capturedID, capturedContent) = (selectedID, editorContent)
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, selectedNoteID == capturedID else { return }
            await performSave(noteID: capturedID, content: capturedContent)
        }
    }
    
    private func performSave(noteID: UUID, content: String) async {
        guard loadError == nil, externalConflict == nil,
              let note = noteStore.notes.first(where: { $0.id == noteID }) else { return }
        let isFirstSave = note.isUnsaved
        do {
            let saveURL: URL
            var collisionName: String?
            if isFirstSave, let newURL = noteStore.resolveFirstSaveCollision(id: noteID) {
                saveURL = newURL
                selectedNoteURL = newURL
                collisionName = newURL.lastPathComponent
            } else {
                saveURL = note.url
            }

            noteStore.markAsSavedLocally(saveURL, content: content)
            try await atomicWrite(content: content, to: saveURL)
            await MainActor.run {
                if selectedNoteID == noteID {
                    originalContent = content
                    isDirty = false
                }
                unsavedNoteIDs.remove(noteID)
                if let idx = noteStore.notes.firstIndex(where: { $0.id == noteID }) {
                    noteStore.notes[idx].isUnsaved = false
                }
                saveError = nil
                if let name = collisionName {
                    withAnimation { externalToastMessage = "File already existed — saved as \(name)" }
                }
                AppDelegate.shared.hasUnsavedChanges = !isDirty
            }
        } catch is CancellationError {
            return
        } catch {
            await MainActor.run {
                saveError = SaveError(fileURL: note.url, error: error, content: content)
                AppDelegate.shared.hasUnsavedChanges = true
            }
        }
    }
    
    private func retrySave(error: SaveError) async {
        do {
            noteStore.markAsSavedLocally(error.fileURL, content: error.content)
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
                    noteStore.markAsSavedLocally(url, content: error.content)
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

private func atomicWrite(content: String, to url: URL) async throws {
    try Task.checkCancellation()

    let data = content.data(using: .utf8)!
    let dir = url.deletingLastPathComponent()
    let tempURL = dir.appendingPathComponent(".neonv-\(UUID().uuidString).tmp")

    defer { try? FileManager.default.removeItem(at: tempURL) }

    try data.write(to: tempURL, options: .atomic)

    try Task.checkCancellation()

    let fileManager = FileManager.default
    do {
        try fileManager.moveItem(at: tempURL, to: url)
    } catch CocoaError.fileWriteFileExists {
        _ = try fileManager.replaceItemAt(url, withItemAt: tempURL)
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

struct FileLoadErrorView: View {
    var fileURL: URL
    var error: Error
    var onShowInFinder: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 48)).foregroundColor(.orange)
            Text("Couldn't Read File").font(.headline)
            Text(fileURL.lastPathComponent).font(.subheadline).foregroundColor(.secondary)
            Text(error.localizedDescription).font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            Text("Check file permissions or iCloud download status").font(.caption)
                .foregroundColor(.secondary).multilineTextAlignment(.center)
            Button("Show in Finder", action: onShowInFinder).buttonStyle(.borderedProminent)
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
                .disableAutocorrection(true)
                .focused($focusedField, equals: .search)
                .onKeyPress { press in
                    // Cmd+Shift+D or Cmd+Period to insert date
                    let isCmdShiftD = press.modifiers.contains([.command, .shift]) &&
                        (press.key == .init("d") || press.key == .init("D"))
                    let isCmdPeriod = press.modifiers.contains(.command) &&
                        !press.modifiers.contains(.shift) && !press.modifiers.contains(.option) &&
                        press.key == .init(".")
                    if isCmdShiftD || isCmdPeriod {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        let dateString = formatter.string(from: Date())
                        text += dateString
                        return .handled
                    }
                    return .ignored
                }
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
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(height: 1)
            .contentShape(Rectangle().inset(by: -4))
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
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(height: 1)
            .contentShape(Rectangle().inset(by: -4))
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
    var onRenameNote: ((NoteFile) -> Void)?
    var onAddTag: ((NoteFile) -> Void)?

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

                        if !note.tags.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(note.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.system(size: 10))
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(3)
                                }
                            }
                        }

                        if !note.contentPreview.isEmpty {
                            Text(note.contentPreview.replacingOccurrences(of: "\n", with: " "))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .tag(note.id)
                    .contextMenu {
                        if !note.isUnsaved, let onAddTag = onAddTag {
                            Button("Add Tags...") {
                                onAddTag(note)
                            }
                        }
                        if !note.isUnsaved, let onRenameNote = onRenameNote {
                            Button("Rename") {
                                onRenameNote(note)
                            }
                        }
                        if let onShowInFinder = onShowInFinder {
                            Button("Show in Finder") {
                                onShowInFinder(note)
                            }
                        }
                        if let onDeleteNote = onDeleteNote {
                            Button("Move to Trash", role: .destructive) {
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
    @Binding var cursorPosition: Int
    @Binding var scrollFraction: CGFloat
    var restoreScrollFraction: CGFloat?
    @FocusState var focusedField: FocusedField?
    @ObservedObject private var settings = AppSettings.shared
    var searchText: String
    var isEditable: Bool = true
    var isHiddenFromFocus: Bool = false
    var onShiftTab: (() -> Void)?
    var onEscape: (() -> Void)?

    var body: some View {
        PlainTextEditor(
            text: $content,
            cursorPosition: $cursorPosition,
            scrollFraction: $scrollFraction,
            restoreScrollFraction: restoreScrollFraction,
            fontSize: CGFloat(settings.fontSize),
            fontFamily: settings.fontFamily,
            isEditable: isEditable,
            isHiddenFromFocus: isHiddenFromFocus,
            showFindBar: showFindBar,
            searchTerms: [],
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
    let onAddTag: () -> Void
    let onNavigateBack: () -> Void
    let onNavigateForward: () -> Void

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
            .onReceive(NotificationCenter.default.publisher(for: .addTag)) { _ in
                onAddTag()
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateBack)) { _ in
                onNavigateBack()
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateForward)) { _ in
                onNavigateForward()
            }
    }
}

#Preview {
    ContentView(noteStore: NoteStore())
}
