import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var noteStore: NoteStore

    init(noteStore: NoteStore) {
        _noteStore = StateObject(wrappedValue: noteStore)
    }

    var body: some View {
        TabView {
            GeneralSettingsTab(noteStore: noteStore)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            EditorSettingsTab()
                .tabItem {
                    Label("Editor", systemImage: "textformat")
                }
        }
        .frame(width: 450, height: 280)
    }
}

struct GeneralSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject var noteStore: NoteStore
    @State private var showEditorPicker = false

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Notes Folder")
                            .font(.headline)
                        if let url = noteStore.selectedFolderURL {
                            Text(url.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("No folder selected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button("Change...") {
                        noteStore.selectFolder()
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            Section {
                Picker("Default File Extension", selection: $settings.defaultExtension) {
                    ForEach(FileExtension.allCases, id: \.self) { ext in
                        Text(ext.displayName).tag(ext)
                    }
                }
                .pickerStyle(.menu)

                Text("New notes will be created with this file extension")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            Section {
                Toggle("Enable Global Hotkey", isOn: $settings.globalHotkeyEnabled)

                if settings.globalHotkeyEnabled {
                    HStack {
                        Text("Summon NeoNV:")
                        Spacer()
                        Text("Ctrl + Space")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Text("Global hotkey requires Accessibility permissions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("External Editor")
                            .font(.headline)
                        Text(settings.externalEditorDisplayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if settings.externalEditorPath != nil {
                        Button("Clear") {
                            settings.externalEditorPath = nil
                        }
                    }

                    Button("Choose...") {
                        showEditorPicker = true
                    }
                }
                .padding(.vertical, 4)

                Text("Open notes in this app with ⌘G")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .fileImporter(
            isPresented: $showEditorPicker,
            allowedContentTypes: [.application],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                settings.externalEditorPath = url.path
            }
        }
    }
}

struct EditorSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Font Size")
                            .font(.headline)
                        Spacer()
                        Text("\(Int(settings.fontSize)) pt")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }

                    Slider(value: $settings.fontSize, in: 9...24, step: 1)

                    HStack {
                        Text("9")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("24")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.headline)

                    Text("The quick brown fox jumps over the lazy dog.")
                        .font(.system(size: settings.fontSize, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(4)
                }
                .padding(.vertical, 4)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView(noteStore: NoteStore())
}
