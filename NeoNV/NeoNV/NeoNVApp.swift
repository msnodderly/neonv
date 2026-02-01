import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var shared = AppDelegate()
    var hasUnsavedChanges = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            self.setupWindowDelegate()
        }
    }

    private func setupWindowDelegate() {
        for window in NSApplication.shared.windows where window.delegate == nil {
            window.delegate = self
        }
    }

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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in NSApplication.shared.windows {
                window.makeKeyAndOrderFront(self)
                return true
            }
        }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let visibleWindows = NSApplication.shared.windows.filter { $0.isVisible && !$0.isMiniaturized }
        if visibleWindows.count <= 1 {
            NSApplication.shared.hide(nil)
            return false
        }
        return true
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

            CommandGroup(after: .toolbar) {
                Button("Toggle Search Bar") {
                    NotificationCenter.default.post(name: .toggleSearchField, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Toggle File List") {
                    NotificationCenter.default.post(name: .toggleFileList, object: nil)
                }

                Button("Toggle Preview") {
                    NotificationCenter.default.post(name: .togglePreview, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)

                Divider()

                Button("Toggle Layout") {
                    NotificationCenter.default.post(name: .toggleLayout, object: nil)
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .printItem) { }

            CommandGroup(replacing: .help) {
                Button("NeoNV Help") {
                    NotificationCenter.default.post(name: .showHelp, object: nil)
                }

                Button("Keyboard Shortcuts") {
                    NotificationCenter.default.post(name: .showKeyboardShortcuts, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
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
    static let showKeyboardShortcuts = Notification.Name("showKeyboardShortcuts")
    static let openInExternalEditor = Notification.Name("openInExternalEditor")
    static let toggleSearchField = Notification.Name("toggleSearchField")
    static let toggleFileList = Notification.Name("toggleFileList")
    static let toggleLayout = Notification.Name("toggleLayout")
}
