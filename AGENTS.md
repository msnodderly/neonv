# Agent Development Notes

This document captures patterns, gotchas, and learnings discovered during AI-assisted development of neonv.

---

## Task Tracking
Use 'bd' for task tracking
bd ready 	List tasks with no open blockers.
bd create "Title" -p 0 	Create a P0 task.
bd dep add <child> <parent> 	Link tasks (blocks, related, parent-child).
bd show <id> 	View task details and audit trail.


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

### Error Handling with Modal Alerts (NSAlert)

For critical errors that require user intervention:

```swift
@State private var saveError: SaveError?

struct SaveError: Identifiable {
    let id = UUID()
    let fileURL: URL
    let error: Error
    let content: String
}

// Present error with SwiftUI alert
.alert(item: $saveError) { error in
    Alert(
        title: Text("Save Failed"),
        message: Text("Failed to save \(error.fileURL.lastPathComponent):\n\n\(error.error.localizedDescription)"),
        primaryButton: .default(Text("Retry")) { /* retry logic */ },
        secondaryButton: .default(Text("More Options...")) { /* show NSAlert */ }
    )
}

// For more complex dialogs, use NSAlert directly
let alert = NSAlert()
alert.messageText = "Save Failed"
alert.informativeText = "Details..."
alert.alertStyle = .critical
alert.addButton(withTitle: "Option 1")
alert.addButton(withTitle: "Option 2")
let response = alert.runModal()
```

**Important:** Use `.disabled(saveError != nil)` to block UI interaction during error states.

### File Creation with Atomic Writes

Create new files safely:

```swift
private func atomicWrite(content: String, to url: URL) async throws {
    try await Task.detached(priority: .userInitiated) {
        let data = content.data(using: .utf8)!
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp")

        try data.write(to: tempURL, options: .atomic)

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: tempURL)
        } else {
            try fileManager.moveItem(at: tempURL, to: url)
        }
    }.value
}
```

**Pattern:** Always write to temp file first, then rename. Prevents corruption on failure.

### Unified Search/Create Pattern

Implement Notational Velocity-style unified input:

```swift
// In search bar, handle Enter key
.onKeyPress(.return) {
    if matchCount > 0 {
        // Select first match
        onNavigateToList()
    } else if !text.isEmpty {
        // Create new note
        onCreateNote()
    }
    return .handled
}

// Visual feedback
if !text.isEmpty {
    Text(matchCount > 0 ? "\(matchCount) match\(matchCount == 1 ? "" : "es")" : "⏎ to create")
        .font(.system(size: 11))
        .foregroundColor(.secondary)
}
```

**Key insight:** Single input for both search and create eliminates decision friction.

### Filename Sanitization

Convert user input to filesystem-safe names:

```swift
private func sanitizeFileName(_ name: String) -> String {
    var sanitized = name.lowercased()
        .replacingOccurrences(of: " ", with: "-")
        .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)

    if sanitized.count > 100 {
        sanitized = String(sanitized.prefix(100))
    }

    if sanitized.isEmpty {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        sanitized = "untitled-\(formatter.string(from: Date()))"
    }

    return sanitized
}
```

**Pattern:** Lowercase, replace spaces with hyphens, remove special chars, truncate, fallback to timestamp.

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



## Landing the Plane

When the user says "let's land the plane", you MUST complete ALL steps below. The plane is NOT landed until git push succeeds. NEVER stop before pushing. NEVER say "ready to push when you are!" - that is a FAILURE.

MANDATORY WORKFLOW - COMPLETE ALL STEPS:

    File beads issues for any remaining work that needs follow-up

    Ensure all quality gates pass (only if code changes were made):
        Run make lint or golangci-lint run ./... (if pre-commit installed: pre-commit run --all-files)
        Run make test or go test ./...
        File P0 issues if quality gates are broken

    Update beads issues - close finished work, update status

    PUSH TO REMOTE - NON-NEGOTIABLE - This step is MANDATORY. Execute ALL commands below:

    # Pull first to catch any remote changes
    git pull --rebase

    # If conflicts in .beads/issues.jsonl, resolve thoughtfully:
    #   - git checkout --theirs .beads/issues.jsonl (accept remote)
    #   - bd import -i .beads/issues.jsonl (re-import)
    #   - Or manual merge, then import

    # Sync the database (exports to JSONL, commits)
    bd sync

    # MANDATORY: Push everything to remote
    # DO NOT STOP BEFORE THIS COMMAND COMPLETES
    git push

    # MANDATORY: Verify push succeeded
    git status  # MUST show "up to date with origin/main"

    CRITICAL RULES:
        The plane has NOT landed until git push completes successfully
        NEVER stop before git push - that leaves work stranded locally
        NEVER say "ready to push when you are!" - YOU must push, not the user
        If git push fails, resolve the issue and retry until it succeeds
        The user is managing multiple agents - unpushed work breaks their coordination workflow

    Clean up git state - Clear old stashes and prune dead remote branches:

    git stash clear                    # Remove old stashes
    git remote prune origin            # Clean up deleted remote branches

    Verify clean state - Ensure all changes are committed AND PUSHED, no untracked files remain

    Choose a follow-up issue for next session
        Provide a prompt for the user to give to you in the next session
        Format: "Continue work on bd-X: [issue title]. [Brief context about what's been done and what's next]"

REMEMBER: Landing the plane means EVERYTHING is pushed to remote. No exceptions. No "ready when you are". PUSH IT.

Example "land the plane" session:

# 1. File remaining work
bd create "Add integration tests for sync" -t task -p 2 --json

# 2. Run quality gates (only if code changes were made)
go test -short ./...
golangci-lint run ./...

# 3. Close finished issues
bd close bd-42 bd-43 --reason "Completed" --json

# 4. PUSH TO REMOTE - MANDATORY, NO STOPPING BEFORE THIS IS DONE
git pull --rebase
# If conflicts in .beads/issues.jsonl, resolve thoughtfully:
#   - git checkout --theirs .beads/issues.jsonl (accept remote)
#   - bd import -i .beads/issues.jsonl (re-import)
#   - Or manual merge, then import
bd sync        # Export/import/commit
git push       # MANDATORY - THE PLANE IS STILL IN THE AIR UNTIL THIS SUCCEEDS
git status     # MUST verify "up to date with origin/main"

# 5. Clean up git state
git stash clear
git remote prune origin

# 6. Verify everything is clean and pushed
git status

# 7. Choose next work
bd ready --json
bd show bd-44 --json

Then provide the user with:

    Summary of what was completed this session
    What issues were filed for follow-up
    Status of quality gates (all passing / issues filed)
    Confirmation that ALL changes have been pushed to remote
    Recommended prompt for next session

CRITICAL: Never end a "land the plane" session without successfully pushing. The user is coordinating multiple agents and unpushed work causes severe rebase conflicts.
Agent Session Workflow

WARNING: DO NOT use bd edit - it opens an interactive editor ($EDITOR) which AI agents cannot use. Use bd update with flags instead:

bd update <id> --description "new description"
bd update <id> --title "new title"
bd update <id> --design "design notes"
bd update <id> --notes "additional notes"
bd update <id> --acceptance "acceptance criteria"

IMPORTANT for AI agents: When you finish making issue changes, always run:

bd sync

This immediately:

    Exports pending changes to JSONL (no 30s wait)
    Commits to git
    Pulls from remote
    Imports any updates
    Pushes to remote

Example agent session:

# Make multiple changes (batched in 30-second window)
bd create "Fix bug" -p 1
bd create "Add tests" -p 1
bd update bd-42 --status in_progress
bd close bd-40 --reason "Completed"

# Force immediate sync at end of session
bd sync

# Now safe to end session - everything is committed and pushed

Why this matters:

    Without bd sync, changes sit in 30-second debounce window
    User might think you pushed but JSONL is still dirty
    bd sync forces immediate flush/commit/push

STRONGLY RECOMMENDED: Install git hooks for automatic sync (prevents stale JSONL problems):

# One-time setup - run this in each beads workspace
bd hooks install

This installs:

    pre-commit - Flushes pending changes immediately before commit (bypasses 30s debounce)
    post-merge - Imports updated JSONL after pull/merge (guaranteed sync)
    pre-push - Exports database to JSONL before push (prevents stale JSONL from reaching remote)
    post-checkout - Imports JSONL after branch checkout (ensures consistency)

Why git hooks matter: Without the pre-push hook, you can have database changes committed locally but stale JSONL pushed to remote, causing multi-workspace divergence. The hooks guarantee DB ↔ JSONL consistency.

Note: Hooks are embedded in the bd binary and work for all bd users (not just source repo users).
