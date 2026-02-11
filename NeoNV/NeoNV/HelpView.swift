import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    
    private let shortcuts = [
        ShortcutCategory(
            title: "Navigation",
            shortcuts: [
                Shortcut(key: "⌘L", description: "Focus search bar"),
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
                Shortcut(key: "⌘⇧D", description: "Insert timestamp"),
                Shortcut(key: "Delete / ⌘Delete", description: "Move selected note to Trash"),
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
            HStack {
                Text("Help")
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
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    appOverviewSection
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    keyboardShortcutsSection
                }
                .padding(.vertical, 16)
            }
        }
        .frame(width: 520, height: 650)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

    private var appOverviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("About NeoNV")
                    .font(.headline)
                Spacer()
                Text(appVersion)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(
                    icon: "bolt.fill",
                    title: "Fast, Frictionless Text Capture",
                    description: "Capture snippets, thoughts, and notes instantly. Never think about saving."
                )
                
                FeatureRow(
                    icon: "magnifyingglass",
                    title: "Instant Search",
                    description: "Find any note in milliseconds with fuzzy full-text search."
                )
                
                FeatureRow(
                    icon: "doc.text",
                    title: "Plain Text Files",
                    description: "Your notes are just .txt, .md, or .org files. No lock-in, no proprietary formats."
                )
                
                FeatureRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Auto-Save",
                    description: "Changes save continuously. Close the app anytime—your work is safe."
                )
                
                FeatureRow(
                    icon: "folder",
                    title: "Your Folder, Your Files",
                    description: "Point NeoNV at any folder. Edit files with any tool—NeoNV doesn't care."
                )
            }
            .padding(.horizontal, 20)
        }
    }
    
    private var keyboardShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard Shortcuts")
                .font(.headline)
                .padding(.horizontal, 20)
            
            LazyVStack(spacing: 0) {
                ForEach(Array(shortcuts.enumerated()), id: \.element.title) { index, category in
                    ShortcutCategoryView(category: category, isLastCategory: index == shortcuts.count - 1)
                }
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    HelpView()
}
