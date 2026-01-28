# Agent Development Notes

Workflows, patterns, and gotchas for AI-assisted development of neonv.

---

## Running the App

```bash
./run.sh  # Builds and launches NeoNV
```

---

## Manual Testing Instructions

When making UI or keyboard-related changes, include step-by-step testing instructions in the PR description:

1. Prerequisites (e.g., "select a notes folder first")
2. Numbered steps to verify each change
3. Expected behavior for each step
4. Note if any shortcut should produce no beep

---

## Task Tracking with `bd`

Use 'bd' for task tracking.

```
bd ready                      # List tasks with no open blockers
bd create "Title" -p 0        # Create a P0 task
bd show <id>                  # View task details
bd update <id> --status in_progress
bd close <id> --reason "..."
bd dep add <child> <parent>   # Link tasks
bd sync --full                # Export/commit/push to main
```

**WARNING:** Do not use `bd edit` — it opens an interactive editor. Use `bd update` with flags instead:

```bash
bd update <id> --description "new description"
bd update <id> --title "new title"
bd update <id> --design "design notes"
bd update <id> --notes "additional notes"
bd update <id> --acceptance "acceptance criteria"
```

---

## Worktree Workflow

Multiple agents can work simultaneously using separate git worktrees. **Always use `bd worktree` instead of `git worktree`** — it automatically configures beads to share the database.

### Setup

```bash
bd worktree create <name> --branch task/<id>-short-description

# IMPORTANT: Commit .gitignore before leaving main
git add .gitignore && git commit -m "chore: Update .gitignore for <name> worktree"
git push
cd <name>
```

**Why commit .gitignore?** `bd worktree create` adds the worktree directory to `.gitignore` (to prevent accidentally committing worktree contents). If you don't commit this change before switching to the worktree, main will be left with a dirty working directory, causing `git pull` to fail later.
### Commands

```bash
bd worktree list    # Show all worktrees with beads status
bd worktree info    # Show current worktree details
bd worktree remove <name>  # Cleanup after merge (includes safety checks)
```

---

## Syncing Changes

The `.beads/issues.jsonl` file is tracked in git and pushes directly to `main` (no PR required).

- `bd sync` — Export only (no commit/push)
- `bd sync --full` — Full sync: export, pull, merge, commit, push

**Always use `bd sync --full`** when you need changes shared.

### Sync Workflow

```bash
git stash --include-untracked
bd sync --full
git stash pop
```

Run sync: before ending sessions, after closing/updating tasks, before pushing feature branches.

### Git Hooks (one-time setup)

```bash
bd hooks install  # Installs pre-commit, post-merge, pre-push, post-checkout hooks
```

---

## Session Completion

### 1. Finalize

```bash
xcodebuild -scheme NeoNV -destination 'platform=macOS' build  # If code changes
bd close <id> --reason "Completed"
git stash --include-untracked && bd sync --full && git stash pop
```

### 2. Push & PR

```bash
git push -u origin task/<branch-name>
gh pr create --title "feat: Description" --body "..."
```

### 3. Cleanup (after merge)

```bash
gh pr merge --squash --delete-branch
git checkout main && git pull && bd sync
bd worktree remove <name>  # If using worktree
```

---

## Resolving Beads Conflicts

```bash
git checkout --theirs .beads/issues.jsonl
bd import -i .beads/issues.jsonl
```

---

## Patterns

### Focus Management (macOS 14+)

Use enum-based `@FocusState` for multi-pane focus:

```swift
enum FocusedField: Hashable {
    case search, noteList, editor
}

@FocusState private var focusedField: FocusedField?

TextField("Search", text: $searchText)
    .focused($focusedField, equals: .search)
```

### Custom Keyboard Navigation

```swift
.onKeyPress { press in
    if press.key == .tab && press.modifiers.contains(.shift) {
        focusedField = .search
        return .handled
    }
    return .ignored  // Let system handle other keys
}
```

Return `.handled` to consume the key (no beep), `.ignored` to pass through.

### List Focus

SwiftUI `List` doesn't naturally accept keyboard focus:

```swift
List(items, selection: $selection) { ... }
    .focusable()
    .focused($focusedField, equals: .noteList)
```

### File Discovery

```swift
guard let enumerator = fileManager.enumerator(
    at: folderURL,
    includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
    options: [.skipsHiddenFiles, .skipsPackageDescendants]
) else { return }

for case let fileURL as URL in enumerator {
    let ext = fileURL.pathExtension.lowercased()
    guard allowedExtensions.contains(ext) else { continue }
    // Fetch resource values during enumeration for efficiency
    let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
}
```

### Atomic File Writes

```swift
private func atomicWrite(content: String, to url: URL) async throws {
    try await Task.detached(priority: .userInitiated) {
        let data = content.data(using: .utf8)!
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp")
        try data.write(to: tempURL, options: .atomic)

        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: url)
        }
    }.value
}
```

### Settings Scene (Cmd+,)

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
        Settings { SettingsView() }
    }
}
```

### Sharing State Between Scenes

Create `@StateObject` in App struct, pass to both scenes:

```swift
@main
struct MyApp: App {
    @StateObject private var sharedStore = DataStore()

    var body: some Scene {
        WindowGroup { ContentView(store: sharedStore) }
        Settings { SettingsView(store: sharedStore) }
    }
}

// Receiving views use @ObservedObject, not @StateObject
struct ContentView: View {
    @ObservedObject var store: DataStore
}
```

### Singleton Settings

```swift
@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize") }
    }

    private init() {
        let stored = UserDefaults.standard.double(forKey: "fontSize")
        self.fontSize = stored > 0 ? stored : 13.0
    }
}
```

### Filename Sanitization

```swift
private func sanitizeFileName(_ name: String) -> String {
    var sanitized = name.lowercased()
        .replacingOccurrences(of: " ", with: "-")
        .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)

    if sanitized.count > 100 { sanitized = String(sanitized.prefix(100)) }
    if sanitized.isEmpty {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        sanitized = "untitled-\(formatter.string(from: Date()))"
    }
    return sanitized
}
```

---

## Philosophy

### The "Beep Audit" Principle

**"Every beep is a bug"** is a UX discovery tool.

When macOS beeps: "The user pressed a key expecting something to happen, but nothing did."

Use beeps diagnostically:
1. Note where user was and what key they pressed
2. Ask: What did the user expect?
3. Implement that behavior, or document why not

Don't suppress beeps — they reveal user expectations.

---

## Gotchas

### `.onKeyPress()` API

```swift
// WRONG - this API doesn't exist
.onKeyPress(.tab, modifiers: .shift) { ... }

// CORRECT
.onKeyPress { press in
    if press.key == .tab && press.modifiers.contains(.shift) {
        return .handled
    }
    return .ignored
}
```

### TextEditor Intercepts Keys Before SwiftUI

`TextEditor` wraps `NSTextView`, which intercepts keys (Shift-Tab, Escape) at AppKit level before `.onKeyPress` sees them.

**Solution:** Use `NSViewRepresentable` with custom `NSTextView` subclass:

```swift
class CustomKeyTextView: NSTextView {
    var onShiftTab: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 && event.modifierFlags.contains(.shift) {
            onShiftTab?()
            return
        }
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}
```
