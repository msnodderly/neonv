import SwiftUI

struct HorizontalNoteListView: View {
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
                    HStack(alignment: .top, spacing: 12) {
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
                        .frame(width: 180, alignment: .leading)

                        if !note.contentPreview.isEmpty {
                            Text(note.contentPreview)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
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
                    if press.key == .downArrow {
                        if let lastNote = notes.last, selectedNoteID == lastNote.id {
                            onTabToEditor()
                            return .handled
                        }
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
