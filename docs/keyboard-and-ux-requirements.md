# Keyboard & UX Requirements

*Implementation Status: ✅ Phase 1 & 2 Complete (v0.9.0)*

This document tracks keyboard navigation and UX requirements. Originally written during prototyping, now reflects production implementation.

## Navigation Flow ✅ IMPLEMENTED

### Search → Note List → Editor

**App launch:**
- **✅ Search box focused by default**
- **✅ User can start typing immediately**

**Forward navigation (Tab / Down Arrow):**
- **✅ From Search:** Tab OR Down Arrow → moves to note list
- **✅ From Note List:** Tab OR Right Arrow → moves to editor
- **✅ In Editor:** Tab inserts tab character (for code/indentation)
- **✅ Enter in List:** Opens note in editor

**Backward navigation (Shift-Tab / Up Arrow / Escape):**
- **✅ From Editor:** Shift-Tab → back to note list, Escape → back to list
- **✅ From Note List:** Shift-Tab → back to search box
- **✅ Up Arrow in note list (first item):** Moves to search box
- **✅ Escape from anywhere:** Returns to search

**Arrow keys in note list:**
- **✅ Up/Down arrows** navigate the list (standard behavior)
- **✅ Works immediately** when list is focused
- **✅ Right Arrow** opens selected note in editor

---

## Essential Keyboard Shortcuts

### ✅ Implemented in v0.9.0

| Shortcut | Action | Status |
|----------|--------|--------|
| **Cmd-L** | Focus search bar | ✅ |
| **Cmd-Shift-L** | Toggle search field visibility | ✅ |
| **Cmd-N** | New note | ✅ |
| **Cmd-P** | Toggle preview mode | ✅ |
| **Cmd-K** | Show keyboard shortcuts reference | ✅ |
| **Cmd-G** | Open in external editor | ✅ |
| **Cmd-Shift-D** | Insert current date (yyyy-MM-dd) | ✅ |
| **Cmd-.** | Insert current date (alternative) | ✅ |
| **Cmd-F** | Find in note | ✅ |
| **Cmd-R** | Show in Finder | ✅ |
| **Cmd-Shift-J** | Toggle layout (vertical/horizontal) | ✅ |
| **Cmd-Z** | Undo (standard macOS) | ✅ |
| **Cmd-Shift-Z** | Redo (standard macOS) | ✅ |
| **Cmd-A** | Select all in current pane | ✅ |
| **Delete / ⌘⌫** | Move selected note to Trash | ✅ |
| **Escape** | Return to search from editor/list | ✅ |
| **Tab/Shift-Tab** | Navigate panes | ✅ |
| **Enter** (in list) | Open selected note | ✅ |
| **Right Arrow** (in list) | Move to editor | ✅ |
| **Down Arrow** (in search) | Move to note list | ✅ |
| **Up/Down** (in list) | Navigate notes | ✅ |
| **Page Up/Down** (in preview) | Scroll by page | ✅ |

### ❌ Not Implemented
- **Global hotkey** to summon app (requires AppKit CGEvent handling)

---

## The "Beep Audit" Principle ✅ ACHIEVED

**Rule:** Every time the app beeps, that's a user expecting something to happen.

**Result:** All expected key combinations now handled. No beeps during normal navigation.

**Successfully resolved beep scenarios:**
- ✅ Tab from search → moves to note list
- ✅ Shift-Tab from editor → cycles back to list
- ✅ Down Arrow in search → moves to note list
- ✅ Up Arrow in search (at top) → stays in search (no action, no beep)
- ✅ Up Arrow in list (at first item) → moves to search
- ✅ Escape from editor/list → returns to search
- ✅ Tab in editor → inserts tab character
- ✅ Right Arrow in list → opens note in editor
- ✅ All navigation keys → graceful handling

**Implementation approach:**
1. ✅ Logged all beep occurrences during prototype testing
2. ✅ Identified expected behavior for each key combination
3. ✅ Implemented handlers using SwiftUI `.onKeyPress()` API
4. ✅ Verified no beeps remain in normal use

---

## File Naming / Display ✅ IMPLEMENTED

### Display name in note list:
- **✅ Primary text:** First ~50 chars of first line
- **✅ Markdown stripping:** Removes `#`, `-`, `*`, `>` decorators from display
- **✅ Content preview:** 2-line snippet shown under path
- **✅ Length:** 50 chars confirmed as good

### Filename display in subtitle:
- **✅ Shows actual filename:** Format like `projects/work/idea.txt`
- **✅ Path context:** Full relative path from notes folder
- **✅ Visual hierarchy:** Path shown in muted color below title

### Filename assignment indicator:
- **✅ Not yet saved:** Shows `[unsaved]` in orange/italic
- **✅ Saved with name:** Shows actual relative path
- **✅ Visual distinction:** Clear difference between saved and unsaved states

### Auto-created subdirectories (v0.9.0+):
- **✅ Nested paths:** First line like `projects/2026/notes` auto-creates directories
- **✅ Sanitization:** Applied to each path component separately
- **✅ Examples:**
  - `work/bug fixes` → `notes/work/bug-fixes.md`
  - `2026/01/daily log` → `notes/2026/01/daily-log.md`

**Fallback behavior (implemented):**
- If first line is empty: `untitled-[yyyyMMdd-HHmmss].ext`
- If first line is only whitespace: treat as empty
- If first line is too long: truncate at 100 characters
- If first line has only special chars: timestamp fallback

---

## Preview Mode ✅ IMPLEMENTED

### Toggle behavior:
- **✅ Cmd-P** - Toggle preview on/off
- **✅ Button in toolbar** - Visual toggle button available
- **✅ Position:** Preview replaces editor pane (not side-by-side)

### Preview focus and scrolling:
- **✅ Implemented:** Preview pane focusable and receives focus by default
- **✅ Keyboard scrolling:** Up/Down arrows, Page Up/Page Down scroll content
- **✅ Line-by-line scrolling:** Up/Down arrows scroll one line at a time
- **✅ Page scrolling:** Page Up/Down scroll by full page

### Smart preview switching:
- **❌ Not working:** Typing characters in preview mode does not switch to edit mode (see Known Issues)
- **Workaround:** Press Cmd-P to manually toggle back to edit mode
- **Expected behavior:** Should auto-switch to edit mode and capture keystroke

### Preview rendering:
- **✅ Markdown:** Full rendering with headers, lists, bold, italic, links, code blocks, tables
- **✅ Org-mode:** Basic rendering with TODO colors, emphasis, code blocks
- **✅ Plain text:** Shows formatted version with proper line spacing
- **✅ Performance:** Renders quickly even for long documents

---

## Focus Indicators ✅ IMPLEMENTED

**Visual cues implemented:**
- **✅ Search bar:** System focus ring appears when focused
- **✅ Note list:** System selection highlight (blue/gray depending on theme)
- **✅ Editor:** Cursor visible and blinking when focused
- **✅ Preview pane:** Receives focus and supports keyboard scrolling

**Implementation decision:** Default macOS focus ring is sufficient - users understand standard system behavior. Custom focus indicators would add visual noise without benefit.

---

## Autosave Behavior ✅ IMPLEMENTED

**When saves occur:**
- **✅ On every keystroke** (debounced 500ms to avoid excessive I/O)
- **✅ On focus loss** from editor
- **✅ On selecting different note**
- **✅ On app quit** (with unsaved changes warning if needed)

**Visual feedback:**
- **✅ Orange dot indicator** in toolbar when unsaved changes exist
- **✅ Silent save** - no toast or flash when save succeeds
- **✅ Loud failure** - modal alert blocks editing if save fails
- **✅ [unsaved] badge** in file list for new notes not yet saved

**Implementation decision:** Silent autosave confirmed as correct choice. Only failures get attention.

---

## Search Behavior ✅ IMPLEMENTED

**Implemented features:**
- **✅ Fuzzy full-text search:** Searches title, path, and content preview
- **✅ Real-time filtering:** Instant results as you type (50ms debounce)
- **✅ Match counter:** Shows "N matches" or "⏮ to create" in search bar
- **✅ Auto-selection:** First match auto-selects when searching
- **✅ Selection memory:** Restores previous selection when clearing search
- **✅ Search highlighting:** Optional highlighting of search terms in editor (toggle in settings)
- **✅ Smart create:** Enter key creates new note if no matches, or navigates to note if matches exist

**Performance:**
- **✅ Fast:** Searches through 1000+ notes instantly
- **✅ Efficient:** Metadata caching prevents repeated file reads
- **✅ No indexing lag:** Results appear immediately without "building index" delays

**Implementation decision:** Fuzzy matching proved worth the complexity - feels natural and fast.

---

## External Edit Detection ✅ IMPLEMENTED

**Behavior when file changes externally:**
1. **✅ If editor is not dirty** (no unsaved changes): auto-reload silently with toast notification
2. **✅ If editor is dirty:** show modal with options:
   - Keep my version (overwrite external change)
   - Use external version (discard my changes)

**Content Hash Tracking (v0.9.0):**
- **✅ SHA256 hash** calculated on file load
- **✅ Smart comparison:** When FSEvents detects change, compares content hash
- **✅ Filters false positives:** If content identical (cloud sync metadata update), silently updates timestamp
- **✅ Real conflicts only:** Only shows dialog when actual content changed
- **✅ Benefits:** Eliminates interruptions from Dropbox/iCloud/Syncthing metadata touches

**Visual feedback:**
- **✅ Toast notification:** "Reloaded — file changed externally"
- **✅ Deleted file toast:** "Deleted externally" when file removed
- **✅ Modal dialog:** Clean two-option modal for real conflicts

---

## Additional Features Implemented

Beyond the original MVP spec, the following features were added based on daily use:

### Layout Flexibility (v0.8.0+)
- **✅ Vertical layout** (default): Sidebar list + editor pane
- **✅ Horizontal layout**: Top list pane + editor pane
- **✅ Toggle:** Cmd-Shift-J switches between modes
- **✅ Persistence:** Layout choice saved across sessions

### UI Customization
- **✅ Collapsible search field:** Drag divider to hide/show search (double-click to restore)
- **✅ Toggle file list visibility:** View menu option to hide/show list
- **✅ Toggle search field visibility:** Cmd-Shift-L to hide/show independently
- **✅ Font customization:** Settings panel for font family and size (8-72pt)
- **✅ Search highlighting:** Optional highlighting of search terms in editor

### Enhanced File Operations
- **✅ Right-click rename** (v0.7.0): Rename with duplicate validation
- **✅ Auto-create subdirectories** (v0.9.0): First line with `/` creates nested folders
- **✅ Content hash tracking:** Smart cloud sync conflict detection
- **✅ 2-line content preview:** Snippet shown in file list
- **✅ Insert current date:** Cmd-Shift-D or Cmd-. inserts `yyyy-MM-dd`

### Editor Features
- **✅ Find in note:** Cmd-F opens find bar within current note
- **✅ Incremental text styling** (v0.9.0): Prevents flickering when typing at bottom
- **✅ External editor integration:** Cmd-G opens note in configured editor

---

## Things We're NOT Doing (Anti-Features)

- No tags (search is enough)
- No folders in UI (filesystem has them, we show flat list)
- No rich text (markdown preview only)
- No collaboration
- No sync (user handles that)
- No export (files are already plain text)
- No themes (use system light/dark mode)

---

## Implementation Decisions (Resolved)

1. **✅ TextEditor performance?** Fast enough for MVP; incremental styling added in v0.9.0 to fix editor flickering with large files
2. **✅ SwiftUI List with 1000+ items?** Handles smoothly with metadata caching and efficient rendering
3. **✅ Preview toggle:** Replaces editor (confirmed correct choice - clean and uncluttered)
4. **✅ Filename display:** Shows extension and full relative path - works excellently
5. **✅ Search bar size:** Collapsible with drag divider (added in v0.8.0) - perfect solution

---

## Implementation Status (v0.9.0)

1. ✅ Basic layout (search, list, editor)
2. ✅ Search filtering (fuzzy full-text with debouncing)
3. ✅ First-line-as-filename display
4. ✅ Preview toggle button (Cmd-P + toolbar button)
5. ✅ Keyboard shortcuts (all major ones implemented and documented)
6. ✅ Performance with 1000+ notes (optimized with metadata caching)
7. ✅ External edit detection (FSEvents + content hash tracking)
8. ✅ Conflict resolution (smart modal with Keep/Use options)
9. ✅ Settings panel (folder, extension, editor, font customization)
10. ✅ Multiple layout modes (vertical/horizontal with Cmd-Shift-J)
11. ✅ Collapsible UI elements (search field, file list toggles)
12. ✅ File operations (rename, delete, show in Finder)
13. ✅ Auto-created subdirectories (v0.9.0)

---

## Known Issues

### Type-to-Exit Preview Not Working
- **Issue:** Typing characters in preview mode does not automatically switch to edit mode
- **Workaround:** Press Cmd-P to manually toggle to edit mode
- **Status:** Tracked in [GitHub issue #87](https://github.com/msnodderly/neonv/issues/87)

---

*Last updated: February 2026 (v0.9.0)*
