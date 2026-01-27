# Agent Development Notes

This document captures patterns, gotchas, and learnings discovered during AI-assisted development of neonv.

---

## Patterns

### Focus Management in SwiftUI (macOS 14+)

**Pattern:** Use enum-based `@FocusState` for multi-pane focus tracking.

```swift
enum FocusedField: Hashable {
    case search
    case noteList
    case editor
}

@FocusState private var focusedField: FocusedField?

// Apply to views
TextField("Search", text: $searchText)
    .focused($focusedField, equals: .search)

// Set focus programmatically
.onAppear {
    focusedField = .search
}
```

### Custom Keyboard Navigation with `.onKeyPress()`

**Pattern:** Use closure form to check key and modifiers together.

```swift
.onKeyPress { press in
    if press.key == .tab && press.modifiers.contains(.shift) {
        focusedField = .search
        return .handled
    }
    return .ignored  // Let system handle other keys
}
```

**Important:** Return `.handled` to consume the key (no beep), `.ignored` to pass through.

### List Focus with `.focusable()`

SwiftUI `List` doesn't naturally accept keyboard focus. Wrap with `.focusable()`:

```swift
List(items, selection: $selection) { item in
    // ...
}
.focusable()
.focused($focusedField, equals: .noteList)
```

### Context-Aware Navigation

Check state before handling keys to enable smart navigation:

```swift
// Up arrow from top of list returns to search
if press.key == .upArrow {
    if let selected = selectedNoteID,
       let firstNote = filteredNotes.first,
       selected == firstNote.id {
        // At top - return to search
        focusedField = .search
        return .handled
    }
    // Not at top - let List handle navigation
    return .ignored
}
```

### Note Row Display Pattern

Two-line display with title and path:

```swift
VStack(alignment: .leading, spacing: 2) {
    Text(displayTitle)
        .font(.system(size: 13, weight: .medium))
        .lineLimit(1)
    Text(path)
        .font(.system(size: 11))
        .foregroundColor(.secondary)
}
```

### Markdown Stripping for Display Titles

```swift
var displayTitle: String {
    var title = rawTitle

    // Strip leading # headers
    if title.hasPrefix("#") {
        title = title.drop(while: { $0 == "#" || $0 == " " }).description
    }
    // Strip list markers
    if title.hasPrefix("- ") || title.hasPrefix("* ") || title.hasPrefix("+ ") {
        title = String(title.dropFirst(2))
    }
    // Strip blockquotes
    if title.hasPrefix("> ") {
        title = String(title.dropFirst(2))
    }

    // Truncate
    if title.count > 50 {
        title = String(title.prefix(47)) + "..."
    }

    return title.isEmpty ? "Untitled" : title
}
```

### File Discovery with FileManager

**Pattern:** Use `FileManager.enumerator` for recursive directory traversal.

```swift
let fileManager = Foundation.FileManager.default
guard let enumerator = fileManager.enumerator(
    at: folderURL,
    includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
    options: [.skipsHiddenFiles, .skipsPackageDescendants]
) else { return }

for case let fileURL as URL in enumerator {
    // Filter by extension
    let ext = fileURL.pathExtension.lowercased()
    guard allowedExtensions.contains(ext) else { continue }

    // Get modification date
    let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
    let modDate = resourceValues?.contentModificationDate ?? Date.distantPast

    // Process file...
}
```

**Important:** Fetch resource values during enumeration for efficiency. Don't make separate calls per file.

### Persistent Storage with UserDefaults

Store folder selection across app launches:

```swift
// Save
UserDefaults.standard.set(url.absoluteString, forKey: "selectedNotesFolder")

// Load
if let storedPath = UserDefaults.standard.string(forKey: "selectedNotesFolder"),
   let url = URL(string: storedPath) {
    selectedFolderURL = url
}
```

**Note:** For sandboxed apps, use security-scoped bookmarks instead of plain paths.

---

## Philosophy

### The "Beep Audit" Principle

**"Every beep is a bug"** is a UX discovery tool, not a directive to suppress beeps.

When macOS beeps, it signals: "The user pressed a key expecting something to happen, but nothing did."

The beep reveals a gap between user expectation and app behavior. Use beeps diagnostically:

1. **Hear a beep** → Note where user was (search/list/editor) and what key they pressed
2. **Ask:** What did the user probably expect to happen?
3. **Implement** that behavior, OR document why not

Don't suppress beeps - they're telling you what users want.

---

## Gotchas

### 1. `.onKeyPress()` API Variants

**Wrong:**
```swift
.onKeyPress(.tab, modifiers: .shift) { ... }  // This API doesn't exist
```

**Correct:**
```swift
.onKeyPress { press in
    if press.key == .tab && press.modifiers.contains(.shift) {
        // handle
        return .handled
    }
    return .ignored
}
```

### 2. TextEditor/NSTextView Intercepts Keys Before SwiftUI

**Problem:** SwiftUI's `TextEditor` wraps `NSTextView`, which intercepts certain keys (like Shift-Tab, Escape) at the AppKit level *before* SwiftUI's `.onKeyPress` handler sees them.

**Wrong approach (doesn't work):**
```swift
TextEditor(text: $content)
    .onKeyPress { press in
        // Shift-Tab never reaches here - NSTextView consumes it first
        if press.key == .tab && press.modifiers.contains(.shift) {
            focusedField = .noteList
            return .handled
        }
        return .ignored
    }
```

**Correct approach:** Use `NSViewRepresentable` with a custom `NSTextView` subclass:
```swift
class CustomKeyTextView: NSTextView {
    var onShiftTab: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Intercept Shift-Tab (keyCode 48 with shift modifier)
        if event.keyCode == 48 && event.modifierFlags.contains(.shift) {
            onShiftTab?()
            return  // Don't pass to super
        }

        // Intercept Escape (keyCode 53)
        if event.keyCode == 53 {
            onEscape?()
            return  // Don't pass to super
        }

        super.keyDown(with: event)
    }
}
```

**Common key codes:**
- Tab: 48
- Escape: 53
- Return: 36
- Space: 49

**Lesson:** When AppKit's default key handling conflicts with your navigation model, you must intercept at the AppKit level, not SwiftUI level.

### 3. HSplitView vs NavigationSplitView

- `NavigationSplitView`: Good for sidebar patterns but has opinionated behavior
- `HSplitView`: More control, better for custom layouts like Alt NV

We use `HSplitView` for the main layout.



---

---

## Implementation Status

| Issue | Status | Notes |
|-------|--------|-------|

---

*Last updated: 2026-01-25*
