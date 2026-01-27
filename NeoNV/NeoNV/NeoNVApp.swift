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
    }
}
