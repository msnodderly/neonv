import SwiftUI

struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss
    
    private let shortcuts = [
        ShortcutCategory(
            title: "Navigation",
            shortcuts: [
                Shortcut(key: "⌘L", description: "Focus search bar"),
                Shortcut(key: "⌘⇧L", description: "Toggle search field visibility"),
                Shortcut(key: "View menu", description: "Toggle file list visibility"),
                Shortcut(key: "Tab / ↓", description: "Move to next pane"),
                Shortcut(key: "Shift + Tab", description: "Move to previous pane"),
                Shortcut(key: "→", description: "Move to editor from list"),
                Shortcut(key: "↑", description: "Move to search from list (first item)"),
                Shortcut(key: "Return", description: "Confirm action / navigate"),
                Shortcut(key: "Escape", description: "Cancel / go back")
            ]
        ),
        ShortcutCategory(
            title: "Actions",
            shortcuts: [
                Shortcut(key: "⌘N", description: "Create new note"),
                Shortcut(key: "⌘P", description: "Toggle markdown preview"),
                Shortcut(key: "⌘G", description: "Open in external editor"),
                Shortcut(key: "Delete", description: "Delete selected note"),
                Shortcut(key: "⌘,", description: "Open settings"),
                Shortcut(key: "⌘K", description: "Show keyboard shortcuts")
            ]
        ),
        ShortcutCategory(
            title: "Editor & Preview",
            shortcuts: [
                Shortcut(key: "Shift + Tab", description: "Return to note list"),
                Shortcut(key: "Escape", description: "Return to note list"),
                Shortcut(key: "Page Up / Down", description: "Scroll preview"),
                Shortcut(key: "↑ / ↓", description: "Scroll preview line by line"),
                Shortcut(key: "Type any key", description: "Switch preview to editor")
            ]
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            Divider()
            
            // Shortcuts content
            ScrollView {
LazyVStack(spacing: 0) {
    ForEach(Array(shortcuts.enumerated()), id: \.element.title) { index, category in
        ShortcutCategoryView(category: category, isLastCategory: index == shortcuts.count - 1)
    }
}
                .padding(.vertical, 16)
            }
        }
        .frame(width: 500, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct ShortcutCategory: Identifiable {
    let id = UUID()
    let title: String
    let shortcuts: [Shortcut]
}

struct Shortcut: Identifiable {
    let id = UUID()
    let key: String
    let description: String
}

struct ShortcutCategoryView: View {
    let category: ShortcutCategory
    let isLastCategory: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category title
            Text(category.title)
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 20)
            
            // Shortcuts in this category
            VStack(spacing: 8) {
                ForEach(category.shortcuts) { shortcut in
                    ShortcutRowView(shortcut: shortcut)
                }
            }
            
            if !isLastCategory {
                Divider()
                    .padding(.vertical, 16)
            }
        }
    }
}

struct ShortcutRowView: View {
    let shortcut: Shortcut
    
    var body: some View {
        HStack {
            Text(shortcut.key)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .frame(width: 120, alignment: .leading)
            
            Text(shortcut.description)
                .font(.body)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
    }
}

#Preview {
    KeyboardShortcutsView()
}