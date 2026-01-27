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
    @FocusState private var focusedField: FocusedField?
    
    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText, focusedField: _focusedField)
            
            Divider()
            
            if noteStore.selectedFolderURL == nil {
                EmptyStateView(onSelectFolder: noteStore.selectFolder)
            } else {
                HSplitView {
                    NoteListView(
                        notes: noteStore.notes,
                        selectedNoteID: $selectedNoteID,
                        focusedField: _focusedField,
                        isLoading: noteStore.isLoading
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
                Button(action: noteStore.selectFolder) {
                    Image(systemName: "folder")
                }
                .help("Select notes folder")
            }
        }
        .onChange(of: selectedNoteID) { _, newID in
            loadSelectedNote(id: newID)
        }
    }
    
    private func loadSelectedNote(id: UUID?) {
        guard let id = id,
              let note = noteStore.notes.first(where: { $0.id == id }) else {
            editorContent = ""
            return
        }
        
        do {
            editorContent = try String(contentsOf: note.url, encoding: .utf8)
        } catch {
            editorContent = ""
        }
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
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search or create...", text: $text)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .search)
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
