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

### Cleaning Up Worktrees

Check status of all worktrees:
```bash
bd worktree list
# For each worktree, check git status and unpushed commits:
git -C <worktree-path> status --short
git -C <worktree-path> log origin/main..HEAD --oneline
```

Check for existing PRs (to identify already-merged work):
```bash
gh pr list --state all --json headRefName,state,title
```

Remove worktrees:
```bash
bd worktree remove <name>          # Safe removal (checks for unpushed work)
bd worktree remove <name> --force  # Force removal (discards local work)
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

### NSViewRepresentable Focus Forwarding

When wrapping an `NSTextView` in an `NSScrollView` within an `NSViewRepresentable`, SwiftUI's `.focused()` modifier targets the `NSScrollView`. To ensure the `NSTextView` becomes the first responder, use a focus-forwarding subclass:

```swift
fileprivate class FocusForwardingScrollView: NSScrollView {
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        if let docView = documentView {
            return window?.makeFirstResponder(docView) ?? false
        }
        return super.becomeFirstResponder()
    }
}
```

### View Swapping Focus Timing

When toggling between views (e.g., Editor vs. Preview) and changing focus in the same action, use `DispatchQueue.main.asyncAfter` with a small delay to allow SwiftUI time to create and attach the new view before it can accept focus:

```swift
private func togglePreview() {
    showPreview.toggle()
    if focusedField == .editor || focusedField == .preview {
        let target: FocusedField = showPreview ? .preview : .editor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedField = target
        }
    }
}
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

### NSTextView Find Bar (NSTextFinder)

`NSTextView.usesFindBar = true` enables the native macOS find bar. Key gotchas:

- **`performTextFinderAction` does not focus the search field.** After showing the find bar, you must manually find the `NSSearchField` in `scrollView.findBarView` and call `window?.makeFirstResponder()` on it:
  ```swift
  // Recursively find NSSearchField in the find bar view hierarchy
  static func focusSearchField(in view: NSView) {
      for subview in view.subviews {
          if let searchField = subview as? NSSearchField {
              searchField.window?.makeFirstResponder(searchField)
              return
          }
          focusSearchField(in: subview)
      }
  }
  ```
  Use `DispatchQueue.main.asyncAfter(deadline: .now() + 0.1)` to let the find bar render first.

- **`super.keyDown(with:)` does NOT dismiss the find bar** when Escape is pressed in the text view. You must programmatically hide it:
  ```swift
  let menuItem = NSMenuItem()
  menuItem.tag = Int(NSTextFinder.Action.hideFindInterface.rawValue)
  performTextFinderAction(menuItem)
  ```

- **Cmd+F should focus the search field even if the find bar is already visible.** Don't gate the focus logic on `!isFindBarVisible` — the user may have navigated away and returned.

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

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
