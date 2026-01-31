import Foundation
import SwiftUI
import Combine

enum LayoutMode: String, CaseIterable {
    case vertical
    case horizontal

    var displayName: String {
        switch self {
        case .vertical: return "Vertical (sidebar)"
        case .horizontal: return "Horizontal (top list)"
        }
    }
}

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
        static let externalEditorPath = "externalEditorPath"
        static let searchHighlightingEnabled = "searchHighlightingEnabled"
        static let isSearchFieldHidden = "isSearchFieldHidden"
        static let isFileListHidden = "isFileListHidden"
        static let layoutMode = "layoutMode"
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

    @Published var externalEditorPath: String? {
        didSet {
            UserDefaults.standard.set(externalEditorPath, forKey: Keys.externalEditorPath)
        }
    }

    @Published var searchHighlightingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(searchHighlightingEnabled, forKey: Keys.searchHighlightingEnabled)
        }
    }

    @Published var isSearchFieldHidden: Bool {
        didSet {
            UserDefaults.standard.set(isSearchFieldHidden, forKey: Keys.isSearchFieldHidden)
        }
    }

    @Published var isFileListHidden: Bool {
        didSet {
            UserDefaults.standard.set(isFileListHidden, forKey: Keys.isFileListHidden)
        }
    }

    @Published var layoutMode: LayoutMode {
        didSet {
            UserDefaults.standard.set(layoutMode.rawValue, forKey: Keys.layoutMode)
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

        // Load external editor path
        self.externalEditorPath = UserDefaults.standard.string(forKey: Keys.externalEditorPath)

        // Load search highlighting preference (default: enabled)
        if UserDefaults.standard.object(forKey: Keys.searchHighlightingEnabled) != nil {
            self.searchHighlightingEnabled = UserDefaults.standard.bool(forKey: Keys.searchHighlightingEnabled)
        } else {
            self.searchHighlightingEnabled = true
        }

        // Load search field visibility (default: visible)
        self.isSearchFieldHidden = UserDefaults.standard.bool(forKey: Keys.isSearchFieldHidden)

        // Load file list visibility (default: visible)
        self.isFileListHidden = UserDefaults.standard.bool(forKey: Keys.isFileListHidden)

        // Load layout mode (default: vertical)
        if let storedLayout = UserDefaults.standard.string(forKey: Keys.layoutMode),
           let mode = LayoutMode(rawValue: storedLayout) {
            self.layoutMode = mode
        } else {
            self.layoutMode = .vertical
        }
    }

    func resetToDefaults() {
        defaultExtension = .markdown
        fontSize = 13.0
        externalEditorPath = nil
        searchHighlightingEnabled = true
        isSearchFieldHidden = false
        isFileListHidden = false
        layoutMode = .vertical
    }

    var externalEditorDisplayName: String {
        guard let path = externalEditorPath else {
            return "Default (System)"
        }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }
}
