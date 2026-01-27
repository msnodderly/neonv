import SwiftUI

enum FocusedField: Hashable {
    case search
    case noteList
    case editor
}

struct ContentView: View {
    @State private var searchText = ""
    @State private var selectedNoteID: UUID?
    @State private var editorContent = ""
    @FocusState private var focusedField: FocusedField?
    
    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText, focusedField: _focusedField)
            
            Divider()
            
            HSplitView {
                NoteListView(
                    selectedNoteID: $selectedNoteID,
                    focusedField: _focusedField
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
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            focusedField = .search
        }
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
    @Binding var selectedNoteID: UUID?
    @FocusState var focusedField: FocusedField?
    
    private let placeholderNotes = [
        (id: UUID(), title: "Welcome to NeoNV", path: "notes/welcome.md"),
        (id: UUID(), title: "Getting Started", path: "docs/getting-started.md"),
        (id: UUID(), title: "Quick Tips", path: "tips.txt")
    ]
    
    var body: some View {
        List(placeholderNotes, id: \.id, selection: $selectedNoteID) { note in
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(note.path)
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
