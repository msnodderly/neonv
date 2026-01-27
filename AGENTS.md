# Agent Development Notes

This document captures workflows, patterns, gotchas, and learnings for AI-assisted development of neonv.

---

## Task Tracking with `bd`

Use 'bd' for task tracking.

```
bd ready                      List tasks with no open blockers
bd create "Title" -p 0        Create a P0 task
bd show <id>                  View task details and audit trail
bd update <id> --status in_progress   Claim a task
bd close <id> --reason "..."  Close a completed task
bd dep add <child> <parent>   Link tasks (blocks, related, parent-child)
bd sync                       Immediately export/commit/push changes
```

**WARNING:** Do NOT use `bd edit` — it opens an interactive editor which AI agents cannot use. Use `bd update` with flags instead:

```bash
bd update <id> --description "new description"
bd update <id> --title "new title"
bd update <id> --design "design notes"
bd update <id> --notes "additional notes"
bd update <id> --acceptance "acceptance criteria"
```

---

## Worktree Workflow (Parallel Agents)

Multiple agents can work simultaneously on different tasks. Each agent must use a separate git worktree to avoid conflicts.

**Always use `bd worktree` instead of `git worktree`** — it automatically configures beads to share the database across all worktrees.

### Creating a Worktree

```bash
bd worktree create <name> --branch task/<id>-short-description
cd <name>
```

Examples:
```bash
bd worktree create auth-feature --branch task/neonv-abc-auth
bd worktree create bugfix-123                  # Branch defaults to "bugfix-123"
bd worktree create ../agents/worker-1          # Create at relative path
```

### Listing Worktrees

```bash
bd worktree list
```

Shows all worktrees with their beads status (shared vs local).

### Checking Current Worktree

```bash
bd worktree info
```

Shows worktree path, branch, main repo location, and beads configuration.

### Why Worktrees?

- Each agent gets an isolated working directory
- No branch-switching conflicts between agents
- Changes stay isolated until PR merge
- Main repo stays clean for other agents to spawn from
- Beads database is automatically shared (via redirect file)

### Cleanup After Merge

```bash
# From main repo directory
bd worktree remove <name>
```

This command includes safety checks:
- Warns about uncommitted changes
- Warns about unpushed commits
- Warns about stashes

Use `--force` to skip checks (not recommended).

---

## Syncing Changes

**CRITICAL:** The `.beads/issues.jsonl` file is tracked in git and changes are pushed directly to `main` (no PR required).

### Command Reference

- `bd sync` — **Export only.** Writes pending changes to `.beads/issues.jsonl` but does NOT commit or push.
- `bd sync --full` — **Full sync.** Exports, pulls, merges, commits, and pushes to remote.

**Always use `bd sync --full`** when you need changes pushed to GitHub.

### When to Sync

Run `bd sync --full` at these points:
1. **Before ending your session** (mandatory)
2. After closing a task
3. After creating/updating tasks
4. Before pushing your feature branch

### How to Sync

**Step 1:** Stash any uncommitted work (required — sync fails with dirty working directory):
```bash
git stash --include-untracked
```

**Step 2:** Run full sync:
```bash
bd sync --full
```

**Step 3:** Restore your work:
```bash
git stash pop
```

This sync:
1. Exports pending changes to `.beads/issues.jsonl`
2. Pulls from remote
3. Merges changes (3-way merge)
4. Commits to current branch
5. Pushes to `origin`

### Why Beads Go Directly to Main

- Task tracking is metadata, not code
- Other agents need immediate visibility of task updates
- PRs are only for code/implementation changes
- Prevents merge conflicts in task tracking

### Verification

**Always verify after `bd sync --full`:**
```bash
git status  # Should show no uncommitted .beads/ changes
git log origin/main -1 --oneline  # Should show recent "bd sync: <timestamp>" commit
```

If `bd sync --full` fails or `.beads/issues.jsonl` shows as modified:
```bash
# Manual sync (last resort)
git stash --include-untracked
git checkout main
git pull
git add .beads/issues.jsonl
git commit -m "chore: Update beads database"
git push origin main
git checkout -  # Return to feature branch
git stash pop
```

### Recommended: Install Git Hooks

```bash
# One-time setup per workspace
bd hooks install
```

This installs:
- **pre-commit** — Flushes pending changes before commit
- **post-merge** — Imports updated JSONL after pull/merge
- **pre-push** — Exports database to JSONL before push
- **post-checkout** — Imports JSONL after branch checkout

---

## Session Completion Procedure

When the user says "let's land the plane" or when your task is complete, follow ALL steps below.

**Important:** Code changes require PR workflow. Beads database changes go directly to `main`.

### 1. Finalize Work

```bash
# Run quality gates (if code changes were made)
xcodebuild -scheme NeoNV -destination 'platform=macOS' build

# Close the task
bd close <id> --reason "Completed"

# Sync beads to main (pushes .beads/issues.jsonl directly to origin/main)
git stash --include-untracked
bd sync --full
git stash pop

# Verify sync succeeded
git status  # Should show no uncommitted .beads/ changes
git log origin/main -1 --oneline  # Should show recent "bd sync: <timestamp>" commit
```

**CRITICAL:** If `bd sync --full` fails or you see uncommitted `.beads/issues.jsonl`, stop and fix before proceeding.

### 2. Push Code and Create PR

```bash
# Push your feature branch (code changes only)
git push -u origin task/<branch-name>

# Create PR for code review
gh pr create --title "feat: Description" --body "Detailed description..."
```

**Note:** The beads database was already pushed to `main` in step 1. The PR only contains code changes.

### 3. Merge (if authorized)

```bash
gh pr merge --squash --delete-branch
```

If waiting for review, stop here and inform the user.

### 4. Sync Local Main (after merge)

```bash
git checkout main
git pull
bd sync  # Import any remote changes to local DB
```

### 5. Cleanup

```bash
bd worktree remove <name>  # If using worktree (includes safety checks)
git branch -d task/<branch-name>  # Delete local branch
git remote prune origin
git status  # Verify clean state
```

### 6. Report to User

Provide:
- Summary of what was completed
- Issues filed for follow-up
- Status of quality gates
- Confirmation that beads were synced to `main`
- Confirmation that code was pushed to feature branch
- PR link (if created)
- Recommended prompt for next session

**CRITICAL:**
- Never end a session without successfully syncing beads (`bd sync`)
- Never end with uncommitted changes in `.beads/issues.jsonl`
- Unpushed beads mean other agents can't see task updates
- Unpushed code causes rebase conflicts

---

## Resolving Beads Conflicts

If conflicts occur in `.beads/issues.jsonl`:

```bash
git checkout --theirs .beads/issues.jsonl  # Accept remote version
bd import -i .beads/issues.jsonl           # Re-import
# Or manually merge, then import
```

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

Don't suppress beeps — they're telling you what users want.

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
