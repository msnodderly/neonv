# Keyboard & UX Requirements

*Discovered through prototype testing - every beep is a friction point to fix*

## Navigation Flow

### Search → Note List → Editor

**App launch:**
- Search box should be focused by default 
- User can start typing immediately

**Forward navigation (Tab / Down Arrow):**
- **From Search:** Tab OR Down Arrow → moves to note list
- **From Note List:** Tab → moves to editor
- **In Editor:** Tab inserts tab character (for code/indentation)

**Backward navigation (Shift-Tab / Up Arrow):**
- **From Editor:** Shift-Tab → back to note list
- **From Note List:** Shift-Tab → back to search box
- **Up Arrow** in note list: navigate up (if at top, go to search?)

**Arrow keys in note list:**
- Up/Down arrows navigate the list (standard behavior)
- Should work immediately when list is focused

---

## Essential Keyboard Shortcuts

### Text Editing
- **Cmd-Z** - Undo (standard macOS)
- **Cmd-Shift-Z** - Redo (standard macOS)
- **Cmd-A** - Select all in current pane

### Navigation
- **Cmd-L** - Return to search bar (like browser address bar)
- **Up/Down arrows** - Navigate note list when focused
- **Enter** or TAB or Right Arrow -  Open selected note from list

### App-Level
- **Cmd-N** - New note (clears editor, focuses it)
- **Cmd-F** - Focus search (alternative to Cmd-L)
- **Esc** - Return to search from anywhere
- **CMD-E** or Ctrl-x-ctrl-e (emacs style) - Open selected note in external editor

---

## The "Beep Audit" Principle

**Rule:** Every time the app beeps, that's a user expecting something to happen.

**Process:**
1. Log where the user was (search/list/editor)
2. Log what key they pressed
3. Log what they probably expected to happen
4. Implement the right behavior or document why not

**Examples from testing:**
- Beep on Tab from search → User expected to move to note list
- Beep on Shift-Tab from editor → User expected to cycle back to list

---

## File Naming / Display

### Display name in note list:
- **Primary text:** Abbreviated first line (~50 chars, ellipsis if longer) 
- **Strip markdown formatting** from display:
  - Remove leading `#` (headers: `# Title` → `Title`)
  - Remove leading `-`, `*`, `+` (list items: `- Task` → `Task`)
  - Remove leading `>` (blockquotes: `> Quote` → `Quote`)
  - Keep the actual content, just remove common markdown decorators
- **Length:** 50 chars feels good for now

### Filename display in subtitle:
- **Show actual filename** as part of path (not just "notes/")
- Format: `notes/meeting-notes.md` or `projects/work/idea.txt`
- Helps user understand what the file is actually called on disk

### Filename assignment indicator:
- **Not yet saved:** Show something like `notes/[unsaved]` or `notes/•••` or italic filename?
- **Saved with name:** Show actual filename
- **Need to design:** Visual distinction between saved/unsaved

**Questions to answer:**
- Does abbreviated first line feel natural? ✅ YES
- What length feels right? ✅ 50 chars is good
- Should we show file extension in list? ✅ YES, in the path subtitle
- How do we handle duplicate first lines? (sanitize + add number suffix?)

**Fallback behavior:**
- If first line is empty: `untitled-[timestamp].txt`
- If first line is only whitespace: treat as empty
- If first line is too long: truncate in display, use full on disk (up to OS limits)

---

## Preview Mode (to test in prototype)

### Toggle behavior:
- **Cmd-P** - Toggle preview (mnemonic: Preview) ✅
- **Button in toolbar** - Visual toggle option ✅

### Preview focus and scrolling:
- **Preview pane must be focusable** and selected by default when entering preview mode
- **Keyboard scrolling:** Up/Down arrows, Page Up/Page Down should scroll content
- Without this, keyboard users are stuck

### Smart preview switching:
- **If in preview mode and user types ANY character** → instantly switch to edit mode
- Cursor should be positioned where typing would naturally insert (end of content? or try to match position?)
- This eliminates the "why isn't my typing working?" confusion

### Preview pane location:
- **Current choice:** Replaces editor (toggle between raw/preview)
- Feels clean and uncluttered ✅

### What to preview:
- Markdown rendering (basic: headers, lists, bold, italic, links)
- Plain text → just shows same as editor (no point)
- Org-mode → leave as plain text for now, plugin later

---

## Focus Indicators

**Problem to solve:** User needs to know which pane is active

**Visual cues needed:**
- Search bar: subtle highlight or border when focused
- Note list: system selection highlight (already works)
- Editor: cursor visible (already works), maybe subtle border?

**Test:** Is the default macOS focus ring enough, or too subtle?

---

## Autosave Behavior (for real MVP)

**When to save:**
- On every keystroke (debounced 500ms)
- On focus loss from editor
- On selecting different note
- On app quit

**Visual feedback:**
- **Subtle:** Small "Saved" indicator that fades after 1s
- **Or:** No feedback (silent autosave, only scream on failure)

**Prototype question:** Do we even need "saved" feedback, or is silence better?

---

## Search Behavior (current prototype is simple substring)

**For MVP, consider:**
- Fuzzy matching (like Cmd-P in editors)
- Search in content, not just filename
- Match highlighting in results

**Prototype observation:** Simple substring filter feels fast. Is fuzzy worth the complexity?

---

## External Edit Detection (for real MVP)

**Behavior when file changes externally:**
1. If editor is **not dirty** (no unsaved changes): auto-reload silently
2. If editor **is dirty**: show modal with options:
   - Keep my version (overwrite external change)
   - Use external version (discard my changes)
   - Save mine to new file (safety net)

**Visual indicator:** Subtle flash or toast: "Updated externally"

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

## Open Questions from Prototype

1. **Is TextEditor fast enough?** Or do we need NSTextView for performance?
2. **Does SwiftUI List handle 1000+ items smoothly?**
3. **Preview toggle:** Replace editor, or side-by-side?
4. **Filename display:** Show extension? Show path for nested folders?
5. **Search bar size:** Current size feels okay, or too prominent?

---

## Next Prototype Tests

1. ✅ Basic layout (search, list, editor)
2. ✅ Search filtering
3. 🔄 First-line-as-filename display
4. 🔄 Preview toggle button
5. ⏭️ Keyboard shortcuts (save for MVP)
6. ⏭️ Performance with 100+ fake notes

---

*This is a living document. Add friction points as you discover them.*
