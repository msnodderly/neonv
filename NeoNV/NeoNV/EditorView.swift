import SwiftUI

struct EditorView: View {
    @Binding var content: String
    @Binding var showFindBar: Bool
    @Binding var cursorPosition: Int
    @FocusState var focusedField: FocusedField?
    @ObservedObject private var settings = AppSettings.shared
    var searchText: String
    var onShiftTab: (() -> Void)?
    var onEscape: (() -> Void)?

    var body: some View {
        PlainTextEditor(
            text: $content,
            cursorPosition: $cursorPosition,
            fontSize: CGFloat(settings.fontSize),
            showFindBar: showFindBar,
            searchTerms: [],
            onShiftTab: onShiftTab,
            onEscape: onEscape
        )
        .focused($focusedField, equals: .editor)
        .onChange(of: showFindBar) { _, newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showFindBar = false
                }
            }
        }
    }
}
