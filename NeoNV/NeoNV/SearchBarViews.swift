import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    @FocusState var focusedField: FocusedField?
    var matchCount: Int
    var onNavigateToList: () -> Void
    var onNavigateToEditor: () -> Void
    var onCreateNote: () -> Void
    var onClearSearch: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search or create...", text: $text)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .search)
                .onKeyPress(.tab) {
                    onNavigateToList()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    onNavigateToList()
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    return .handled
                }
                .onKeyPress(.return) {
                    if matchCount == 1 {
                        onNavigateToEditor()
                    } else if matchCount > 1 {
                        onNavigateToList()
                    } else if !text.isEmpty {
                        onCreateNote()
                    }
                    return .handled
                }
                .onKeyPress(.escape) {
                    onClearSearch()
                    return .handled
                }

            if !text.isEmpty {
                Text(matchCount > 0 ? "\(matchCount) match\(matchCount == 1 ? "" : "es")" : "⏎ to create")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.trailing, 4)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct CollapsibleSearchDivider: View {
    @Binding var isSearchHidden: Bool
    var onHide: () -> Void
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(height: 1)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation.height
                    }
                    .onEnded { value in
                        if value.translation.height < -20 {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSearchHidden = true
                            }
                            onHide()
                        }
                    }
            )
            .help("Drag up to hide search field")
    }
}

struct ExpandableSearchDivider: View {
    @Binding var isSearchHidden: Bool
    var onExpand: () -> Void
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(height: 1)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation.height
                    }
                    .onEnded { value in
                        if value.translation.height > 10 {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSearchHidden = false
                            }
                            onExpand()
                        }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearchHidden = false
                }
                onExpand()
            }
            .help("Drag down or double-click to show search field (⌘L)")
    }
}
