import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared = AppDelegate()
    var hasUnsavedChanges = false
    private var mouseMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApp.windows.first {
            window.setFrameAutosaveName("NeoNVMainWindow")
        }

        // Terminal launches don't activate the app; when the user explicitly
        // passed a folder on the command line, bring the window forward.
        if NoteStore.launchFolderArgument() != nil {
            NSApp.activate(ignoringOtherApps: true)
        }

        // Monitor mouse back/forward buttons (buttons 3 and 4 on multi-button mice).
        // NSEvent button numbers: 0=left, 1=right, 2=middle, 3=back, 4=forward
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { event in
            if event.buttonNumber == 3 {
                NotificationCenter.default.post(name: .navigateBack, object: nil)
                return nil // consume the event
            } else if event.buttonNumber == 4 {
                NotificationCenter.default.post(name: .navigateForward, object: nil)
                return nil
            }
            return event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Single-window app: closing the window quits. This also means the
        // app can never save a "no windows" restoration state, which used to
        // strand command-line launches with an invisible app.
        return true
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
}

@main
struct NeoNVApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var noteStore = NoteStore()

    init() {
        Self.migrateSandboxContainerPreferencesIfNeeded()
    }

    /// One-time import of preferences written by earlier sandboxed builds.
    /// Those builds stored UserDefaults inside the app container, which the
    /// un-sandboxed app no longer reads — without this import, existing users
    /// would lose their saved notes folder and settings on upgrade.
    private static func migrateSandboxContainerPreferencesIfNeeded() {
        let defaults = UserDefaults.standard
        let migrationKey = "didMigrateSandboxContainerPreferences"
        guard !defaults.bool(forKey: migrationKey) else { return }

        // When running sandboxed, NSHomeDirectory() already points inside the
        // container, so this path doesn't exist and the import is skipped.
        let containerPlist = NSHomeDirectory()
            + "/Library/Containers/net.area51a.NeoNV/Data/Library/Preferences/net.area51a.NeoNV.plist"
        if let imported = NSDictionary(contentsOfFile: containerPlist) as? [String: Any] {
            for (key, value) in imported where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: migrationKey)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(noteStore: noteStore)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    let hasVisibleWindow = NSApp.windows.contains { window in
                        window.isVisible && window.className.contains("AppKitWindow")
                    }
                    if hasVisibleWindow {
                        NotificationCenter.default.post(name: .createNewNote, object: nil)
                    } else {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            NotificationCenter.default.post(name: .createNewNote, object: nil)
                        }
                    }
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
                Button("Add Tags...") {
                    NotificationCenter.default.post(name: .addTag, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                Button("Toggle Search Bar") {
                    NotificationCenter.default.post(name: .toggleSearchField, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Toggle File List") {
                    NotificationCenter.default.post(name: .toggleFileList, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("Toggle Preview") {
                    NotificationCenter.default.post(name: .togglePreview, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)

                Divider()

                Button("Toggle Layout") {
                    NotificationCenter.default.post(name: .toggleLayout, object: nil)
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])

                Button("Toggle Layout") {
                    NotificationCenter.default.post(name: .toggleLayout, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .control])
                .hidden()
            }

            CommandGroup(before: .toolbar) {
                Button("Go Back") {
                    NotificationCenter.default.post(name: .navigateBack, object: nil)
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("Go Forward") {
                    NotificationCenter.default.post(name: .navigateForward, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)

                Divider()
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
                Button("Move to Trash") {
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
    static let addTag = Notification.Name("addTag")
    static let navigateBack = Notification.Name("navigateBack")
    static let navigateForward = Notification.Name("navigateForward")
}
