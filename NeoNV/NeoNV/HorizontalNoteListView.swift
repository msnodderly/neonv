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
    var onRenameNote: ((NoteFile) -> Void)?
    var onAddTag: ((NoteFile) -> Void)?

    @ObservedObject private var settings = AppSettings.shared

    private var searchTerms: [String] {
        guard settings.searchHighlightingEnabled, !searchText.isEmpty else { return [] }
        return [searchText]
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func formattedDate(_ date: Date) -> String {
        let now = Date()
        if Calendar.current.isDateInToday(date) {
            return Self.relativeDateFormatter.localizedString(for: date, relativeTo: now)
        }
        return Self.dateFormatter.string(from: date)
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
                                font: .system(size: 12, weight: .medium),
                                color: .primary
                            )
                            .lineLimit(1)

                            Text(note.url.lastPathComponent)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)

                            if !note.tags.isEmpty {
                                HStack(spacing: 4) {
                                    ForEach(note.tags, id: \.self) { tag in
                                        Text(tag)
                                            .font(.system(size: 9))
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 3)
                                            .padding(.vertical, 1)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(3)
                                    }
                                }
                            }
                        }
                        .frame(width: 180, alignment: .leading)

                        if !note.contentPreview.isEmpty {
                            Text(note.contentPreview.replacingOccurrences(of: "\n", with: " "))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Spacer()
                                .frame(maxWidth: .infinity)
                        }

                        Text(formattedDate(note.modificationDate))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(width: 120, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
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
