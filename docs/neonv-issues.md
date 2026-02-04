# neonv: Implementation Issues

This document breaks down the product spec into discrete, actionable issues suitable for GitHub Issues or similar task tracking. 

This document is essentially the recipe to recreate neonv from scratch.


---

### Test Data
Created `testnotes/` folder with 13 test files to verify file discovery and display.

---

## Prototype Learnings Summary (January 2026)

A SwiftUI prototype was built and tested. Key findings that affect implementation:

### Validated (Keep As-Is)
- Three-pane layout works well (search top, list left, editor right)
- ~50 character truncated titles feel right
- SwiftUI `List` + `TextEditor` feel responsive (tested with 10 items)
- `.onKeyPress()` (macOS 14+) handles custom keyboard navigation
- `@FocusState` enables programmatic focus management
- Preview toggle button + Cmd-P shortcut is intuitive

### Additions (Non-Negotiable for MVP)
- **Every beep is a bug** - Full keyboard navigation required from day one
- **Search box must be focused on launch** - User starts typing immediately
- **Tab cycles through panes**: Search → List → Editor (with Shift-Tab reverse)
- **Down arrow from search** selects first note and moves to list
- **First-line-as-filename** with markdown stripping in display
- **Unsaved indicator**: `[unsaved]` in orange italic for new notes
- **Preview must be keyboard-scrollable** and type-to-exit enabled

### Technical Notes from Prototype
- SwiftUI keyboard handling uses closure form: `press.key` and `press.modifiers`
- Metal shader cache can lock during build - delete `/var/folders/.../com.apple.metal/`
- May need AppKit for: global hotkey, NSTextView at scale, complex keyboard edge cases



---

## Phase 0: Project Setup

### SETUP-001: Initialize GitHub Repository

**Type:** Setup  
**Priority:** P0 (Blocker)  
**Estimate:** 30 min

**Description:**  
Create the GitHub repository with appropriate initial structure.

**Acceptance Criteria:**
- [ ] Repository created with name TBD (pending final app name)
- [ ] README with project description and vision statement
- [x] GPLv3 license file
- [ ] `.gitignore` for Xcode/Swift projects
- [ ] Initial commit

**Notes:**  
Consider repo naming—if app name changes later, repo rename is easy but better to decide early.

---

### SETUP-002: Create Xcode Project with Universal Binary Target

**Type:** Setup
**Priority:** P0 (Blocker)
**Estimate:** 1 hour

**Description:**
Initialize Xcode project configured for macOS app with universal binary support (arm64 + x86_64).

**Acceptance Criteria:**
- [ ] Xcode project created as macOS App
- [ ] SwiftUI lifecycle selected
- [ ] Deployment target: **macOS 14.0 (Sonoma)** (Required for `.onKeyPress` support)
- [ ] Architectures: Universal (arm64 + x86_64)
- [ ] Bundle identifier set (e.g., `com.yourname.neonv`)
- [ ] Project builds and runs empty window
- [ ] Project committed to repo

**Technical Notes:**
- Use SwiftUI App lifecycle, not AppKit AppDelegate (can add later if needed)
- Verify universal binary: `lipo -info` on built executable should show both architectures
- **Prototype exists:** `neonvPrototype/` has a working Xcode project for reference
- **Critical:** macOS 14+ is required to use `.onKeyPress` for keyboard navigation

---

### SETUP-003: Verify Local Build and Run

**Type:** Setup  
**Priority:** P0 (Blocker)  
**Estimate:** 30 min

**Description:**  
Confirm development environment works end-to-end with free Apple ID.

**Acceptance Criteria:**
- [ ] App builds without errors
- [ ] App runs from Xcode
- [ ] App runs when launched directly from build folder
- [ ] No code signing errors (local development signing)

**Notes:**  
Document any setup steps required for a fresh machine.

---

## Phase 1: MVP Core

### MVP-001: Basic Window with Three-Pane Layout

**Type:** Feature
**Priority:** P0
**Estimate:** 2-3 hours
**Dependencies:** SETUP-002

**Description:**
Create the main window with the foundational three-pane layout: search bar at top, file list on left, editor on right.

**Acceptance Criteria:**
- [x] Single window app
- [x] Search bar/text field at top spanning full width (with space for preview toggle button)
- [x] Left pane: placeholder list view (can be empty)
- [x] Right pane: placeholder text editor
- [x] Resizable split between left and right panes
- [ ] Window remembers size/position between launches
- [x] **Search box focused on app launch** (user can start typing immediately)

**Technical Notes:**
- Use `HSplitView` for pane layout (prototype validated this works well)
- Use `@FocusState` for programmatic focus management
- Consider `NSWindow` state restoration for position memory
- Prototype code in `neonvPrototype/ContentView.swift` shows working layout

**UI Mockup:**
```
┌─────────────────────────────────────────────┐
│ [Search box]                      [F] [P]   │  ← P = preview toggle, F = Folder browser
├──────────────┬──────────────────────────────┤
│ File List    │ Editor Pane                  │
│ (empty)      │ (empty)                      │
└──────────────┴──────────────────────────────┘
```

---

### MVP-002: Text Editor View

**Type:** Feature  
**Priority:** P0  
**Estimate:** 2-3 hours  
**Dependencies:** MVP-001

**Description:**  
Implement a functional plain text editor in the right pane.

**Acceptance Criteria:**
- [ ] Multi-line text editing works
- [ ] Standard text editing shortcuts (Cmd+C, Cmd+V, Cmd+Z, etc.)
- [ ] Monospace or system font (configurable later)
- [ ] No rich text—paste strips formatting automatically
- [ ] Editor content accessible programmatically for saving

**Technical Notes:**
- `TextEditor` in SwiftUI is basic; may need `NSTextView` via `NSViewRepresentable` for better control
- Test paste behavior—ensure RTF/HTML paste becomes plain text
- Consider using `NSTextView` from the start to avoid SwiftUI `TextEditor` limitations

**Open Question:**  
SwiftUI `TextEditor` vs wrapped `NSTextView`? Recommend spiking both to compare.

---

### MVP-003: Folder Selection and File Discovery 

**Type:** Feature
**Priority:** P0
**Estimate:** 2-3 hours
**Dependencies:** MVP-001

**Description:**
Allow user to select a folder; enumerate all text files within it (recursively).

**Acceptance Criteria:**
- [ ] User can select folder via standard macOS open panel
- [ ] App remembers selected folder between launches
- [ ] Discovers all `.txt`, `.md`, `.markdown`, `.org`, `.text` files recursively (case-insensitive)
- [ ] Returns list of file paths with metadata (name, modification date)
- [ ] Handles empty folders gracefully (shows empty state UI)
- [ ] Handles folders with 1000+ files without hanging
- [ ] Folder change button in UI

**Implementation Notes:**
- Created `FileDiscoveryManager` class with `@Published` noteFiles array
- Used `FileManager.enumerator` with resource keys for efficient traversal
- Stored folder path in UserDefaults (will need security-scoped bookmarks for sandboxing)
- Empty state UI shows when no folder selected
- Folder button in search bar to change folders
- File extension matching is case-insensitive (.MD, .md, .Md all work)


---

### MVP-004: File List View (Sorted by Modification Time) 

**Type:** Feature
**Priority:** P0
**Estimate:** 2-3 hours
**Dependencies:** MVP-003

**Description:**
Display discovered files in left pane, sorted by modification time (most recent first).

**Acceptance Criteria:**
- [ ] Files displayed as list in left pane
- [ ] Sorted by modification date, newest first
- [ ] **Primary text: First line of file content** (not filename)
- [ ] **Truncate to ~50 characters** with ellipsis if longer
- [ j **Strip markdown formatting** from display (see rules below)
- [ ] **Secondary text: path/filename.ext** in muted color
- [ ] Selecting a file loads it in editor
- [ ] Visual indication of selected file
- [ ] Empty state when no files found

**Markdown Stripping Rules (display only, file unchanged):**
| Raw First Line | Displayed As |
|----------------|--------------|
| `# Meeting Notes` | `Meeting Notes` |
| `## Project Update` | `Project Update` |
| `- Buy milk` | `Buy milk` |
| `* Task item` | `Task item` |
| `> Important quote` | `Important quote` |

**Technical Notes:**
- Use SwiftUI `List` with selection binding
- File model should include: path, content (or first line), modification date
- Prototype has working markdown stripping code in `FakeNote.stripMarkdownFormatting()`
- SwiftUI `List` felt responsive in prototype with 10 items

**Display Format (Updated from prototype):**
```
Meeting with design team          ← first line, stripped, ~50 chars
  work/meeting-notes.md           ← path + filename, muted

Buy milk, fix bug in auth...      ← truncated with ellipsis
  notes/daily-todos.md

Random idea about CRDTs
  ideas/[unsaved]                 ← orange, italic for unsaved
```

---

### MVP-005: Load File into Editor 

**Type:** Feature
**Priority:** P0
**Estimate:** 1-2 hours
**Dependencies:** MVP-002, MVP-004

**Description:**
When a file is selected in the list, load its contents into the editor.

**Acceptance Criteria:**
- [ ] Clicking file in list loads content into editor
- [ ] Large files (1MB+) load without blocking UI (needs scale testing)
- [ ] UTF-8 encoding handled correctly
- [ ] Graceful error handling for unreadable files
- [ ] Editor becomes editable after load

**Implementation Notes:**
- Implemented `loadContent(for:)` method in FileDiscoveryManager
- Uses `String(contentsOf:encoding:)` with error handling
- Content loaded synchronously (async optimization deferred)
- onChange handler updates editor when selection changes


---

### MVP-006: Auto-Save on Edit (Atomic Write)

**Type:** Feature  
**Priority:** P0 (Critical)  
**Estimate:** 3-4 hours  
**Dependencies:** MVP-005

**Description:**  
Implement continuous auto-save that writes changes to disk safely using atomic operations.

**Acceptance Criteria:**
- [ ] Changes saved automatically after brief debounce (300-500ms of no typing)
- [ ] Uses atomic write: write to temp file, then rename
- [ ] Verifies write succeeded before considering "saved"
- [ ] Dirty indicator shown while unsaved changes exist
- [ ] No data loss on app crash (last debounced save persists)

**Technical Notes:**
- Use `String.write(to:atomically:encoding:)` with `atomically: true`
- Implement debounce with `DispatchWorkItem` or Combine
- Track dirty state: set true on edit, false on successful save
- Consider keeping previous version until new version confirmed

**Data Integrity Requirements:**
This is the most critical feature. Every edit must eventually reach disk safely.

---

### MVP-007: Save Failure Handling (Loud Errors)

**Type:** Feature  
**Priority:** P0 (Critical)  
**Estimate:** 2-3 hours  
**Dependencies:** MVP-006

**Description:**  
When auto-save fails, immediately alert the user and prevent data loss.

**Acceptance Criteria:**
- [ ] Save failure triggers modal alert (not dismissible notification)
- [ ] Alert shows: file path, error description
- [ ] Further editing blocked until resolved
- [ ] Recovery options presented:
  - Retry save
  - Save to alternate location
  - Copy content to clipboard
  - Show file in Finder
- [ ] App cannot be quit with unsaved changes without warning

**Technical Notes:**
- Catch all errors from write operation
- Modal alert via `NSAlert` or SwiftUI `.alert`
- Block editor input while error modal displayed
- Test with: disk full, read-only folder, file locked by another process

**Test Scenarios:**
1. Remove write permission from folder mid-edit
2. Fill disk during save
3. Delete file externally during edit
4. Network folder becomes unavailable (if applicable)

---

### MVP-008: Basic Fuzzy Search

**Type:** Feature  
**Priority:** P0  
**Estimate:** 3-4 hours  
**Dependencies:** MVP-004

**Description:**  
Implement fuzzy search that filters the file list as user types in search bar.

**Acceptance Criteria:**
- [ ] Typing in search bar filters file list in real-time
- [ ] Search matches against filename and file contents
- [ ] Fuzzy matching (e.g., "mtg nts" matches "meeting-notes")
- [ ] Results update as each character typed (<50ms perceived)
- [ ] Empty search shows all files (sorted by modification time)
- [ ] Case-insensitive matching

**Technical Notes:**
- Start simple: substring matching, then add fuzzy
- For content search: may need in-memory index for speed
- Consider caching file contents on folder load for search performance
- Fuzzy algorithm options: simple character sequence, Levenshtein, or Smith-Waterman

**Performance Target:**  
Search across 1000 files must feel instant (<100ms).

---

### MVP-009: Unified Search/Create Bar

**Type:** Feature  
**Priority:** P0  
**Estimate:** 2-3 hours  
**Dependencies:** MVP-008

**Description:**  
Unify search and file creation in single input. If search has no matches, Enter creates new file.

**Acceptance Criteria:**
- [ ] Search bar filters existing files as user types
- [ ] If matches exist: Enter selects top match
- [ ] If no matches: Enter creates new file with search text as content/title
- [ ] Visual indication of mode: "X matches" vs "Enter to create"
- [ ] Escape clears search and returns to full list
- [ ] Newly created file immediately selected and editable

**Technical Notes:**
- Track match count and display in UI
- On create: use search text as first line, derive filename from it
- New file should be saved immediately (empty is fine, will get content)

**UX Detail:**
```
Search: "meeting notes"
Status: "3 matches" or "No matches - Enter to create"
```

---

### MVP-010: New File Creation with Auto-Naming

**Type:** Feature  
**Priority:** P0  
**Estimate:** 2 hours  
**Dependencies:** MVP-009, MVP-006

**Description:**  
When creating new file, automatically derive filename from first line of content.

**Acceptance Criteria:**
- [ ] New file created when Enter pressed with no search matches
- [ ] Filename derived from first line (sanitized for filesystem)
- [ ] If first line empty/unsuitable, use timestamp: `note-2024-01-15-143022`
- [ ] File extension matches user preference (.txt, .md, or .org)
- [ ] Filename sanitization: remove/replace invalid characters
- [ ] Handle filename conflicts (append number if exists)

**Sanitization Rules:**
- Replace `/\:*?"<>|` with `-`
- Trim whitespace
- Truncate to reasonable length (50 chars?)
- Handle empty result → timestamp fallback

---

### MVP-011: Unsaved Note Indicator

**Type:** Feature
**Priority:** P0
**Estimate:** 1-2 hours
**Dependencies:** MVP-004, MVP-010

**Description:**
Visually distinguish notes that haven't been saved to disk yet.

**Acceptance Criteria:**
- [ ] New notes show `[unsaved]` instead of filename in path display
- [ ] Unsaved indicator styled: orange color, italic text
- [ ] Once saved, shows actual filename
- [ ] Indicator updates immediately when file is written to disk

**Display:**
```
My new note content here
  notes/[unsaved]          ← orange, italic

After first save becomes:
My new note content here
  notes/my-new-note.md     ← normal secondary color
```

**Technical Notes:**
- Track `saved` boolean on note model
- Prototype has working style in `ContentView.swift` lines 140-142

---

### MVP-012: Basic Keyboard Navigation (Tab Cycling) 

**Type:** Feature
**Priority:** P0 (Critical - "Every beep is a bug")
**Estimate:** 3-4 hours
**Dependencies:** MVP-001, MVP-004, MVP-002

**Description:**
Implement full keyboard navigation between panes. Users must never need the mouse for basic navigation.

**Acceptance Criteria:**
- [ ] **App launch:** Search box focused automatically
- [ ] **Tab from Search:** Select first filtered note, move focus to list
- [ ] **Down Arrow from Search:** Same as Tab (select first note, focus list)
- [ ] **Tab from List:** Move focus to editor
- [ ] **Shift-Tab from Editor:** Move focus back to list
- [ ] **Shift-Tab from List:** Move focus back to search
- [ ] **Tab in Editor:** Insert tab character (for code/indentation)
- [ ] **Escape from Editor:** Return to list pane
- [ ] **Up Arrow from top of list:** Return to search
- [ ] **Right Arrow from list:** Focus editor

**Key Mapping Table:**
| Context | Key | Action |
|---------|-----|--------|
| Search | Tab | Select first note, focus list |
| Search | Down Arrow | Select first note, focus list |
| Search | Up Arrow | Do nothing (stay in search, NO BEEP) |
| List | Tab | Focus editor |
| List | Shift-Tab | Focus search |
| List | Up/Down | Navigate notes (default behavior) |
| Editor | Shift-Tab | Focus list |
| Editor | Tab | Insert tab character |

**Technical Notes:**
- Use `@FocusState` with enum for focus tracking
- Use `.onKeyPress()` for custom key handling (macOS 14+)
- Prototype has working implementation in `ContentView.swift`
- Key syntax: `press.key == .tab && press.modifiers.contains(.shift)`

**Test Plan:**
1. Launch app → cursor should be in search box
2. Press Tab → first note selected, list has focus
3. Press Tab again → editor has focus
4. Press Shift-Tab → list has focus
5. Press Shift-Tab → search has focus

---

## Phase 2: Polish

### POLISH-001: Extended Keyboard Shortcuts

**Type:** Feature
**Priority:** P1
**Estimate:** 2-3 hours
**Dependencies:** MVP-012

**Description:**
Additional keyboard shortcuts beyond basic Tab navigation (which is in MVP-012).

**Acceptance Criteria:**
- [ ] **Cmd-L:** Focus search bar from anywhere and **select current search terms** (like browser address bar)
- [ ] **Cmd-N:** Create new note (clears editor, focuses it)
- [ ] **Cmd-P:** Toggle preview mode (see POLISH-006)
- [ ] **Cmd-Z / Cmd-Shift-Z:** Undo/Redo working correctly
- [ ] **Cmd-A:** Select all in current pane
- [ ] **Esc:** Return focus to search, clear search text (works from list and editor)
- [ ] **Enter in Search:** If matches exist, select top match; if no matches, create new note
- [ ] **Enter in List:** Focus editor for selected note

**Technical Notes:**
- Use `.keyboardShortcut()` for Cmd+ shortcuts
- Prototype has working Cmd-P implementation
- Undo/Redo should work per-note (not global across all files)

**Reference:**
Full keyboard mapping in `keyboard-and-ux-requirements.md`

---

### POLISH-009: Search Within Note (Cmd-F)

**Type:** Feature
**Priority:** P1
**Estimate:** 2 hours
**Dependencies:** MVP-002

**Description:**
Implement standard "Find" functionality within the currently selected note in the editor.

**Acceptance Criteria:**
- [ ] **Cmd-F:** Shows a search field within the editor pane
- [ ] Highlights matches within the text
- [ ] **Enter / Shift-Enter:** Cycle through next/previous matches
- [ ] **Esc:** Dismisses the find bar and returns focus to editor

**Technical Notes:**
- If using `NSTextView`, use `isIncrementalSearchingEnabled` or standard find bar integration
- Ensure it doesn't conflict with the global search bar

---

### POLISH-010: Open in External Editor (Cmd-G)

**Type:** Feature
**Priority:** P1
**Estimate:** 2 hours
**Dependencies:** MVP-005

**Description:**
Allow users to quickly open the current note in an external text editor of their choice.

**Acceptance Criteria:**
- [ ] **Cmd-G** (or configurable shortcut like **Ctrl-X Ctrl-E**): Opens the current file in the default system editor
- [ ] Provide a setting to specify a preferred editor (e.g., VS Code, MacVim)
- [ ] App detects when the file is saved externally and reloads (see POLISH-004)

**Technical Notes:**
- Use `NSWorkspace.shared.open()` or `Process` to launch the external application
- Pass the file URL to the external tool

---

### POLISH-011: Show in Finder

**Type:** Feature
**Priority:** P2
**Estimate:** 1 hour
**Dependencies:** MVP-004

**Description:**
Command to reveal the selected note file in the macOS Finder.

**Acceptance Criteria:**
- [ ] Menu item and/or shortcut to "Show in Finder"
- [ ] Opens Finder window with the file selected
- [ ] Works for files in nested directories

**Technical Notes:**
- Use `NSWorkspace.shared.activateFileViewerSelecting([fileURL])`

---

### POLISH-012: Search Term Highlighting

**Type:** Feature
**Priority:** P1
**Estimate:** 3-4 hours
**Dependencies:** MVP-008

**Description:**
Highlight search terms within the file list previews and the editor.

**Acceptance Criteria:**
- [ ] Search terms are visually highlighted in the file list titles/subtitles
- [ ] Search terms are highlighted within the editor content when first loading a search result
- [ ] Highlighting can be toggled in settings (standard NV feature)

**Technical Notes:**
- Use `AttributedString` with background colors for highlighting
- Ensure highlighting is performant during rapid search updates

---

### POLISH-002: Global Hotkey to Summon App

**Type:** Feature  
**Priority:** P1  
**Estimate:** 2-3 hours  
**Dependencies:** MVP-001

**Description:**  
System-wide keyboard shortcut to show/focus the app from anywhere.

**Acceptance Criteria:**
- [ ] Default hotkey: Cmd+Shift+N (configurable later)
- [ ] Hotkey works when app is in background
- [ ] Hotkey works when app is hidden
- [ ] If app not running, hotkey launches it
- [ ] Brings window to front and focuses search bar
- [ ] Works across all Spaces/desktops

**Technical Notes:**
- Use `CGEvent.tapCreate` or `MASShortcut` library
- May require Accessibility permissions
- Test with multiple monitors, Spaces, full-screen apps

---

### POLISH-003: FSEvents File Watching

**Type:** Feature  
**Priority:** P1  
**Estimate:** 3-4 hours  
**Dependencies:** MVP-004

**Description:**  
Monitor the notes folder for external changes and update UI accordingly.

**Acceptance Criteria:**
- [ ] Detect new files added externally → add to list
- [ ] Detect files deleted externally → remove from list
- [ ] Detect files renamed externally → update list
- [ ] Detect file content changes externally → see POLISH-004
- [ ] Batch rapid changes (don't update on every event)
- [ ] Works with nested directories

**Technical Notes:**
- Use `FSEvents` API via `DispatchSource.makeFileSystemObjectSource` or `FSEventStream`
- Debounce events (100-200ms) to batch rapid changes
- May need to re-scan directory on some event types

---

### POLISH-004: External Edit Detection and Reload

**Type:** Feature  
**Priority:** P1  
**Estimate:** 2-3 hours  
**Dependencies:** POLISH-003

**Description:**  
When currently-open file is modified externally, handle gracefully.

**Acceptance Criteria:**
- [ ] If file changed externally AND local buffer clean: auto-reload silently
- [ ] Show subtle indicator: "Updated externally" toast (2 seconds)
- [ ] If file changed externally AND local buffer dirty: show conflict dialog
- [ ] Conflict dialog options: Keep mine, Use external, View diff (stretch)
- [ ] Never silently overwrite unsaved local changes

**Conflict Dialog:**
```
"meeting-notes.md" was modified externally.

You have unsaved changes. What would you like to do?

[Keep My Changes] [Load External Version] [Cancel]
```

---

### POLISH-005: Settings Panel

**Type:** Feature  
**Priority:** P1  
**Estimate:** 3-4 hours  
**Dependencies:** MVP-003

**Description:**  
Settings window for user configuration.

**Acceptance Criteria:**
- [ ] Accessible via Cmd+, (standard macOS)
- [ ] Settings:
  - Notes folder location (with browse button)
  - Default file extension (.txt, .md, .org)
  - Font size (or use system default)
  - Global hotkey customization (stretch)
- [ ] Settings persist between launches
- [ ] Changes apply immediately (no restart required)

**Technical Notes:**
- Use `@AppStorage` for UserDefaults integration
- Standard SwiftUI Settings scene or custom window

---

### POLISH-006: Markdown Preview Toggle

**Type:** Feature
**Priority:** P1 (upgraded based on prototype feedback)
**Estimate:** 4-6 hours
**Dependencies:** MVP-002, MVP-012

**Description:**
Optional preview pane showing rendered markdown, with full keyboard support.

**Acceptance Criteria:**
- [ ] **Toggle:** Cmd-P or toolbar button next to search bar
- [ ] **Position:** Preview replaces editor (not side-by-side)
- [ ] **Keyboard scrollable:** Preview pane receives focus, Up/Down/PageUp/PageDown scroll
- [ ] **Type-to-exit:** Any letter/number key switches to editor mode instantly
- [ ] **Shift-Tab:** Returns focus to note list
- [ ] Renders standard markdown: headers, bold, italic, links, code blocks, lists
- [ ] Preview is read-only (editing only in editor mode)

**Type-to-Exit Behavior:**
When in preview mode and user presses any letter/number:
1. Instantly switch to editor mode
2. Focus editor
3. Capture the keystroke in editor
This eliminates "why isn't my typing working?" confusion.

**Technical Notes:**
- Prototype has working toggle button and Cmd-P shortcut
- Use `.onKeyPress()` to detect typing in preview and switch modes
- Options for rendering: `AttributedString`, `WKWebView`, or native `Text` with markdown
- Keep it simple—don't need full GFM, just basics

**Prototype Reference:**
`ContentView.swift` lines 191-211 show preview mode structure (without keyboard scroll)

---

### POLISH-007: Performance Optimization for Large File Sets

**Type:** Technical  
**Priority:** P1  
**Estimate:** 4-6 hours  
**Dependencies:** MVP-008

**Description:**  
Ensure app remains fast with 1000+ files.

**Acceptance Criteria:**
- [ ] App startup with 5000 files: <1 second to usable
- [ ] Search across 5000 files: <100ms per keystroke
- [ ] Memory usage reasonable (<200MB with 5000 files cached)
- [ ] File list scrolling: 60fps
- [ ] No UI freezes during any operation

**Technical Notes:**
- Profile with Instruments
- Consider lazy loading file contents (load on first search, not on startup)
- Virtual list rendering for file list if needed
- Background indexing with progress indicator

**Test Dataset:**  
Create script to generate 5000 dummy text files of varying sizes.

---

### POLISH-008: Nested Folder Path Display

**Type:** Feature  
**Priority:** P2  
**Estimate:** 1-2 hours  
**Dependencies:** MVP-004

**Description:**  
Show relative path for files in nested directories.

**Acceptance Criteria:**
- [ ] Files in root show no path indicator
- [ ] Files in subdirectories show relative path below filename
- [ ] Path displayed in muted/secondary text style
- [ ] Path is relative to notes folder root

**Already partially spec'd in MVP-004, ensure implementation matches:**
```
meeting-notes
  projects/work/

quick-thought

todo-list
  personal/
```

---

## Phase 3: Daily Use Validation

### VALIDATE-001: Daily Use Tracking

**Type:** Process  
**Priority:** P1  
**Estimate:** Ongoing

**Description:**  
Track daily use to validate the app solves the problem.

**Acceptance Criteria:**
- [ ] Use app as primary text capture tool for 30 consecutive days
- [ ] Document friction points as encountered
- [ ] Document missing features that cause reaching for other tools
- [ ] Track: files created, searches performed, saves (if logging added)

**Output:**  
List of issues to address before considering "done."

---

### VALIDATE-002: Edge Case Documentation

**Type:** Process  
**Priority:** P1  
**Estimate:** Ongoing

**Description:**  
Document edge cases discovered during daily use.

**Examples to watch for:**
- Unicode filenames
- Very long filenames
- Very large files (10MB+)
- Files with unusual extensions
- Symlinks in notes folder
- Network drives (if tested)
- iCloud sync conflicts
- Files open in multiple apps simultaneously

**Output:**  
Issues filed for each edge case requiring handling.

---

## Phase 4: Distribution (When Ready)

### DIST-001: Apple Developer Account Setup

**Type:** Setup  
**Priority:** P2 (Deferred)  
**Estimate:** 1-2 hours  
**Prerequisites:** Phase 3 complete, decision to distribute

**Description:**  
Enroll in Apple Developer Program for code signing.

**Acceptance Criteria:**
- [ ] Enrolled in Apple Developer Program ($99/year)
- [ ] Developer ID Application certificate created
- [ ] Certificate installed in Keychain

---

### DIST-002: Code Signing Configuration

**Type:** Setup  
**Priority:** P2 (Deferred)  
**Estimate:** 1-2 hours  
**Dependencies:** DIST-001

**Description:**  
Configure Xcode project for Developer ID signing.

**Acceptance Criteria:**
- [ ] Signing configured for "Developer ID Application"
- [ ] Hardened Runtime enabled
- [ ] Build succeeds with signing
- [ ] `codesign -v` validates the built app

---

### DIST-003: Notarization Pipeline

**Type:** Setup  
**Priority:** P2 (Deferred)  
**Estimate:** 2-3 hours  
**Dependencies:** DIST-002

**Description:**  
Set up notarization with Apple.

**Acceptance Criteria:**
- [ ] App-specific password created for notarization
- [ ] Can notarize via `xcrun notarytool`
- [ ] Notarization ticket stapled to app
- [ ] App passes Gatekeeper on clean Mac

**Commands to document:**
```bash
xcrun notarytool submit App.zip --apple-id ... --password ... --team-id ...
xcrun stapler staple App.app
```

---

### DIST-004: DMG Creation

**Type:** Setup  
**Priority:** P2 (Deferred)  
**Estimate:** 1-2 hours  
**Dependencies:** DIST-003

**Description:**  
Create drag-to-install DMG for distribution.

**Acceptance Criteria:**
- [ ] DMG contains app and Applications folder alias
- [ ] Custom background image (optional but nice)
- [ ] Window size and icon positions set
- [ ] DMG is signed and notarized
- [ ] Opens correctly, drag-to-install works

**Tools:**  
`create-dmg` or `hdiutil` with configuration.

---

### DIST-005: GitHub Releases Setup

**Type:** Setup  
**Priority:** P2 (Deferred)  
**Estimate:** 1 hour  
**Dependencies:** DIST-004

**Description:**  
Configure GitHub Releases for distributing builds.

**Acceptance Criteria:**
- [ ] First release created with DMG attached
- [ ] Release notes template established
- [ ] Semantic versioning documented (v1.0.0 format)
- [ ] Download URL is stable/predictable for Homebrew

---

### DIST-006: Homebrew Cask Formula

**Type:** Setup  
**Priority:** P2 (Deferred)  
**Estimate:** 1-2 hours  
**Dependencies:** DIST-005

**Description:**  
Create and submit Homebrew Cask formula.

**Acceptance Criteria:**
- [ ] Cask formula written and tested locally
- [ ] `brew install --cask ./alt-nv.rb` works
- [ ] PR submitted to homebrew-cask (or personal tap)
- [ ] Formula approved and merged

---

### POLISH-013: Hide Search Field on Drag

**Type:** Feature
**Priority:** P2
**Estimate:** 2 hours

**Description:**
Allow hiding the search field by dragging the divider to the top or left of the window (classic NV behavior).

**Acceptance Criteria:**
- [ ] Dragging the primary divider to its limit hides the search field
- [ ] Visual indicator or shortcut to reveal it again
- [ ] Remembers hidden state

---

## Phase 5: Post-MVP / Plugins

### PLUG-001: Double-Bracket Wiki-Links

**Type:** Feature
**Priority:** P2
**Estimate:** 4-6 hours

**Description:**
Implement wiki-style linking between notes using `[[double brackets]]`.

**Acceptance Criteria:**
- [ ] Text between `[[` and `]]` is recognized as a link
- [ ] Clicking a link (or Cmd-Click) opens the corresponding note
- [ ] Auto-complete note titles while typing inside brackets
- [ ] If linked note doesn't exist, offer to create it

---

### PLUG-002: TaskPaper-style Strikethrough (`@done`)

**Type:** Feature
**Priority:** P2
**Estimate:** 2-3 hours

**Description:**
Support TaskPaper-compatible strikethrough formatting for tasks.

**Acceptance Criteria:**
- [ ] Lines containing the `@done` tag are rendered with strikethrough in the editor/preview
- [ ] (Optional) Shortcut to toggle `@done` on current line

---

### PLUG-003: Horizontal Layout Option

**Type:** Feature
**Priority:** P2
**Estimate:** 4-6 hours

**Description:**
Provide an alternative layout where the file list is at the top (horizontal) instead of the side.

**Acceptance Criteria:**
- [ ] Setting to toggle between Vertical (default) and Horizontal layouts
- [ ] Horizontal layout shows multi-line previews in the list
- [ ] Search bar remains at the top

---

### PLUG-004: Transparent Database Encryption

**Type:** Feature
**Priority:** P3
**Estimate:** 8-12 hours

**Description:**
Optional encryption for note content on disk.

**Acceptance Criteria:**
- [ ] Option to encrypt the notes folder with a master password
- [ ] Files are encrypted/decrypted transparently by the app
- [ ] Uses standard strong encryption (e.g., AES-256)

---

### PLUG-005: Tagging Support (OpenMeta/Spotlight)

**Type:** Feature
**Priority:** P2
**Estimate:** 6-8 hours

**Description:**
Support for tagging notes, potentially using macOS OpenMeta or Spotlight-compatible tags.

**Acceptance Criteria:**
- [ ] Add/Edit tags for selected notes
- [ ] Auto-complete tags while typing
- [ ] Search notes by tags using the main search bar
- [ ] Sync tags to file metadata (OpenMeta)

---

### PLUG-006: Automatic List-Bullet Formatting

**Type:** Feature
**Priority:** P2
**Estimate:** 3-4 hours

**Description:**
Improve the editing experience with automatic list continuation and formatting.

**Acceptance Criteria:**
- [ ] Pressing Enter on a list line (`* `, `- `, `1. `) automatically starts the next list item
- [ ] Indent/Outdent list items with Tab/Shift-Tab
- [ ] Smart conversion of standard markdown list markers

---

## Appendix: Issue Labels

Suggested labels for issue tracking:

| Label | Description |
|-------|-------------|
| `phase-0` | Project setup |
| `phase-1` | MVP core |
| `phase-2` | Polish |
| `phase-3` | Validation |
| `phase-4` | Distribution |
| `priority-p0` | Must have for phase completion |
| `priority-p1` | Should have |
| `priority-p2` | Nice to have / deferred |
| `type-feature` | New functionality |
| `type-bug` | Defect |
| `type-tech-debt` | Technical improvement |
| `type-setup` | Project/environment setup |
| `data-integrity` | Related to never losing data |

---

## Appendix: Dependency Graph

```
SETUP-001 ─┬─► SETUP-002 ─► SETUP-003
           │
           └─► MVP-001 ─┬─► MVP-002 ─┬─► MVP-005 ─► MVP-006 ─► MVP-007
                        │            │
                        │            └─► MVP-012 ─► POLISH-001
                        │                   │
                        │                   └─► POLISH-006
                        │
                        ├─► MVP-003 ─► MVP-004 ─┬─► MVP-005
                        │                       │
                        │                       ├─► MVP-008 ─► MVP-009 ─► MVP-010 ─► MVP-011
                        │                       │
                        │                       ├─► MVP-012
                        │                       │
                        │                       └─► POLISH-003 ─► POLISH-004
                        │
                        └─► POLISH-002

MVP-003 ─► POLISH-005
MVP-008 ─► POLISH-007
MVP-004 ─► POLISH-008

VALIDATE-* ─► DIST-001 ─► DIST-002 ─► DIST-003 ─► DIST-004 ─► DIST-005 ─► DIST-006
```

**New Issues from Prototype:**
- MVP-011: Unsaved Note Indicator
- MVP-012: Basic Keyboard Navigation (Tab Cycling) - **Critical path item**

---

## Appendix: Implementation Starting Point

For an agent beginning implementation, start here:

### Priority Order (MVP)
1. **SETUP-002** - Create Xcode project (or use existing `neonvPrototype/` as reference)
2. **MVP-001** - Three-pane layout with search focus on launch
3. **MVP-012** - Keyboard navigation (do this early, "every beep is a bug")
4. **MVP-002** - Text editor
5. **MVP-003** - Folder selection and file discovery
6. **MVP-004** - File list with first-line display
7. **MVP-005** - Load file into editor
8. **MVP-006** - Auto-save (critical for data integrity)
9. **MVP-007** - Save failure handling
10. **MVP-008** - Basic search
11. **MVP-009** - Unified search/create
12. **MVP-010** - Auto-naming
13. **MVP-011** - Unsaved indicator

### Key Files to Reference
- `alt-nv-product-spec.md` - Full product specification
- `keyboard-and-ux-requirements.md` - Detailed keyboard navigation specs
- `prototype-learnings.md` - What worked and what didn't in prototype
- `neonvPrototype/neonvPrototype/ContentView.swift` - Working SwiftUI code for layout/keyboard

### Technical Decisions Already Made
- **Language:** Swift + SwiftUI (with AppKit fallbacks if needed)
- **macOS Target:** 13+ (Ventura), but keyboard handling uses macOS 14+ APIs
- **Layout:** `HSplitView` for panes, `@FocusState` for focus management
- **Keyboard:** `.onKeyPress()` with closure form for custom handling

---
