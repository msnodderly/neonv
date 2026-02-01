import SwiftUI

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
