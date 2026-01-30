import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared = AppDelegate()
    var hasUnsavedChanges = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if hasUnsavedChanges {
            let alert = NSAlert()
            alert.messageText = "Unsaved Changes"
            alert.informativeText = "There are unsaved changes. Quitting now may result in data loss. Are you sure you want to quit?"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Quit Anyway")

            if alert.runModal() == .alertSecondButtonReturn {
                return .terminateNow
            } else {
                return .terminateCancel
            }
        }
        return .terminateNow
    }
}

@main
struct NeoNVApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var noteStore = NoteStore()

    var body: some Scene {
        WindowGroup {
            ContentView(noteStore: noteStore)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    NotificationCenter.default.post(name: .createNewNote, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(after: .textEditing) {
                Button("Focus Search") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Toggle Preview") {
                    NotificationCenter.default.post(name: .togglePreview, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)

                Divider()

                Button("Find in Note") {
                    NotificationCenter.default.post(name: .findInNote, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Open in External Editor") {
                    NotificationCenter.default.post(name: .openInExternalEditor, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Show in Finder") {
                    NotificationCenter.default.post(name: .showInFinder, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandGroup(replacing: .printItem) { }

            CommandGroup(replacing: .help) {
                Button("NeoNV Help") {
                    NotificationCenter.default.post(name: .showHelp, object: nil)
                }
            }

            CommandGroup(after: .pasteboard) {
                Button("Delete Note") {
                    NotificationCenter.default.post(name: .deleteNote, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [])
            }
        }

        Settings {
            SettingsView(noteStore: noteStore)
        }
    }
}

extension Notification.Name {
    static let focusSearch = Notification.Name("focusSearch")
    static let createNewNote = Notification.Name("createNewNote")
    static let togglePreview = Notification.Name("togglePreview")
    static let deleteNote = Notification.Name("deleteNote")
    static let findInNote = Notification.Name("findInNote")
    static let showInFinder = Notification.Name("showInFinder")
    static let showHelp = Notification.Name("showHelp")
    static let openInExternalEditor = Notification.Name("openInExternalEditor")
}
