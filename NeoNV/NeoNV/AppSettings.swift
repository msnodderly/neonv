import Foundation
import SwiftUI
import Combine

enum FileExtension: String, CaseIterable {
    case markdown = "md"
    case text = "txt"
    case org = "org"

    var displayName: String {
        switch self {
        case .markdown: return "Markdown (.md)"
        case .text: return "Plain Text (.txt)"
        case .org: return "Org Mode (.org)"
        }
    }
}

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let defaultExtension = "defaultFileExtension"
        static let fontSize = "editorFontSize"
        static let globalHotkey = "globalHotkey"
        static let externalEditorPath = "externalEditorPath"
    }

    @Published var defaultExtension: FileExtension {
        didSet {
            UserDefaults.standard.set(defaultExtension.rawValue, forKey: Keys.defaultExtension)
        }
    }

    @Published var fontSize: Double {
        didSet {
            UserDefaults.standard.set(fontSize, forKey: Keys.fontSize)
        }
    }

    @Published var globalHotkeyEnabled: Bool {
        didSet {
            UserDefaults.standard.set(globalHotkeyEnabled, forKey: Keys.globalHotkey)
        }
    }

    @Published var externalEditorPath: String? {
        didSet {
            UserDefaults.standard.set(externalEditorPath, forKey: Keys.externalEditorPath)
        }
    }

    private init() {
        // Load default extension
        if let storedExtension = UserDefaults.standard.string(forKey: Keys.defaultExtension),
           let ext = FileExtension(rawValue: storedExtension) {
            self.defaultExtension = ext
        } else {
            self.defaultExtension = .markdown
        }

        // Load font size (default 13)
        let storedFontSize = UserDefaults.standard.double(forKey: Keys.fontSize)
        self.fontSize = storedFontSize > 0 ? storedFontSize : 13.0

        // Load global hotkey setting
        self.globalHotkeyEnabled = UserDefaults.standard.bool(forKey: Keys.globalHotkey)

        // Load external editor path
        self.externalEditorPath = UserDefaults.standard.string(forKey: Keys.externalEditorPath)
    }

    func resetToDefaults() {
        defaultExtension = .markdown
        fontSize = 13.0
        globalHotkeyEnabled = false
        externalEditorPath = nil
    }

    var externalEditorDisplayName: String {
        guard let path = externalEditorPath else {
            return "Default (System)"
        }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }
}
