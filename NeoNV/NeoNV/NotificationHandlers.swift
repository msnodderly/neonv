import SwiftUI

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
    }
}
