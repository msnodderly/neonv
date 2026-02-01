import SwiftUI

// MARK: - File Operations & Save Logic

extension ContentView {
    func deleteNote(_ note: NoteFile) {
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

    func togglePreview() {
        let wasFocusedInEditorOrPreview = (focusedField == .editor || focusedField == .preview)
        showPreview.toggle()

        if wasFocusedInEditorOrPreview {
            let target: FocusedField = showPreview ? .preview : .editor
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = target
            }
        }
    }

    func toggleSearchField() {
        settings.isSearchFieldHidden.toggle()
        if settings.isSearchFieldHidden {
            if focusedField == .search {
                focusedField = .editor
            }
        } else {
            focusedField = .search
        }
    }

    func toggleFileList() {
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

    func toggleLayout() {
        withAnimation(.easeInOut(duration: 0.2)) {
            settings.layoutMode = settings.layoutMode == .vertical ? .horizontal : .vertical
        }
        if settings.isSearchFieldHidden {
            settings.isSearchFieldHidden = false
        }
        focusedField = .search
    }

    func switchToEditor() {
        showPreview = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedField = .editor
        }
    }

    func openInExternalEditor() {
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

    func showInFinder() {
        guard let url = selectedNoteURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func handleExternalChange(_ change: ExternalChangeEvent) {
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

    func createNewNoteFromShortcut() {
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

    func autoSelectTopMatch() {
        if searchText.isEmpty {
            if let manualID = lastManualSelection,
               noteStore.notes.contains(where: { $0.id == manualID }) {
                selectedNoteID = manualID
            }
            previousSearchWasEmpty = true
        } else {
            if previousSearchWasEmpty, let currentID = selectedNoteID {
                lastManualSelection = currentID
            }

            if let firstMatch = filteredNotes.first {
                selectedNoteID = firstMatch.id
            }

            previousSearchWasEmpty = false
        }
    }

    func loadSelectedNote(id: UUID?) {
        guard let id = id,
              let note = noteStore.notes.first(where: { $0.id == id }) else {
            selectedNoteURL = nil
            originalContent = ""
            editorContent = ""
            cursorPosition = 0
            isDirty = false
            return
        }
        selectedNoteURL = note.url

        if unsavedNoteIDs.contains(id) {
            originalContent = ""
            editorContent = ""
            cursorPosition = 0
            isDirty = false
            return
        }

        Task {
            do {
                let content = try await loadFileAsync(url: note.url)
                await MainActor.run {
                    originalContent = content
                    editorContent = content
                    cursorPosition = 0
                    isDirty = false
                    unsavedNoteIDs.remove(id)
                }
            } catch {
                let errorContent = "Error loading file: \(error.localizedDescription)"
                await MainActor.run {
                    originalContent = errorContent
                    editorContent = errorContent
                    cursorPosition = 0
                    isDirty = false
                    unsavedNoteIDs.remove(id)
                }
            }
        }
    }

    func loadFileAsync(url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try String(contentsOf: url, encoding: .utf8)
        }.value
    }

    func navigateToList() {
        if selectedNoteID == nil, let firstNote = filteredNotes.first {
            selectedNoteID = firstNote.id
        }
        focusedField = .noteList
    }

    func createNewNote() {
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

    func clearSearch() {
        searchText = ""
    }

    func sanitizeFileName(_ name: String) -> String {
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

    func scheduleAutoSave() {
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

    func performSave() async {
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

    func atomicWrite(content: String, to url: URL) async throws {
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

    func retrySave(error: SaveError) async {
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

    func showSaveErrorSheet(error: SaveError) {
        let alert = NSAlert()
        alert.messageText = "Save Failed"
        alert.informativeText = """
            Failed to save \(error.fileURL.lastPathComponent):\
            \n\n\(error.error.localizedDescription)\
            \n\nWhat would you like to do?
            """
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

    func saveToAlternateLocation(error: SaveError) {
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

    func copyToClipboard(error: SaveError) {
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

    func showInFinder(error: SaveError) {
        NSWorkspace.shared.selectFile(error.fileURL.path, inFileViewerRootedAtPath: error.fileURL.deletingLastPathComponent().path)
    }
}
