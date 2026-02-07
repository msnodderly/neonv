import Foundation

/// Tracks a browser-style back/forward navigation history of note UUIDs.
///
/// Call `push(_:)` whenever the user navigates to a new note (selection change,
/// create, search result click, etc.). Call `goBack()` / `goForward()` to
/// navigate the stack. The history automatically collapses duplicate adjacent
/// entries and caps itself at a reasonable depth.
@MainActor
final class NavigationHistory: ObservableObject {
    private var backStack: [UUID] = []
    private var forwardStack: [UUID] = []

    /// Whether a navigation is currently being performed by the history itself.
    /// When true, selection changes should NOT push to the history.
    private(set) var isNavigating = false

    private let maxDepth = 50

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// Record that the user navigated to `noteID`.
    /// Clears the forward stack (like a browser).
    func push(_ noteID: UUID) {
        guard !isNavigating else { return }
        // Avoid duplicate adjacent entries
        if backStack.last == noteID { return }
        backStack.append(noteID)
        if backStack.count > maxDepth {
            backStack.removeFirst(backStack.count - maxDepth)
        }
        forwardStack.removeAll()
    }

    /// Navigate back. Returns the note ID to select, or nil if at the beginning.
    func goBack(current: UUID?) -> UUID? {
        guard !backStack.isEmpty else { return nil }
        // The top of backStack is the current note, so we need to pop it
        // and push it onto forward, then return the new top.
        if let current = current {
            forwardStack.append(current)
        }
        // Pop entries until we find one different from current
        while let previous = backStack.popLast() {
            if previous != current {
                isNavigating = true
                defer { isNavigating = false }
                return previous
            }
            // Same as current, push to forward and keep popping
            forwardStack.append(previous)
        }
        return nil
    }

    /// Navigate forward. Returns the note ID to select, or nil if at the end.
    func goForward(current: UUID?) -> UUID? {
        guard !forwardStack.isEmpty else { return nil }
        if let current = current {
            backStack.append(current)
        }
        while let next = forwardStack.popLast() {
            if next != current {
                isNavigating = true
                defer { isNavigating = false }
                return next
            }
            backStack.append(next)
        }
        return nil
    }
}
