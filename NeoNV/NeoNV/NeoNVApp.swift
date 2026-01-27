import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var noteStore: NoteStore?
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let noteStore = noteStore, noteStore.isDirty else {
            return .terminateNow
        }
        
        let alert = NSAlert()
        alert.messageText = "Unsaved Changes"
        alert.informativeText = "You have unsaved changes. Do you want to save before quitting?"
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            return .terminateNow
        } else {
            return .terminateCancel
        }
    }
}

@main
struct NeoNVApp: App {
    @StateObject private var noteStore = NoteStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView(noteStore: noteStore)
                .onAppear {
                    appDelegate.noteStore = noteStore
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 600)
    }
}
