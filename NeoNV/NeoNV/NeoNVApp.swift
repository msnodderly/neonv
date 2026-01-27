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

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(after: .newItem) {
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
            }
        }
    }
}

extension Notification.Name {
    static let focusSearch = Notification.Name("focusSearch")
    static let createNewNote = Notification.Name("createNewNote")
}
