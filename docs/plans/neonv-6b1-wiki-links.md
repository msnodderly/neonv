# Plan: Double-Bracket Wiki-Links (neonv-6b1)

## Goal
Implement wiki-style linking between notes using `[[double brackets]]`. Links should be clickable to navigate, support auto-completion, and offer to create notes if they don't exist.

## User Experience
1.  **Editing**:
    *   User types `[[`.
    *   App suggests available note titles (auto-complete).
    *   User selects one or keeps typing `[[New Idea]]`.
    *   Text appears as `[[New Idea]]`.
    *   If "New Idea" exists, it's colored **Blue**.
    *   If "New Idea" does not exist, it's colored **Orange** (ghost link).
2.  **Navigation**:
    *   User Clicks (or Cmd-Clicks) on `[[New Idea]]`.
    *   If note exists: Editor switches to that note.
    *   If note missing: App prompts "Create 'New Idea'?" (or auto-creates).
3.  **Preview**:
    *   Wiki-links are rendered as clickable links.
    *   Same navigation logic applies.

## Technical Architecture

### 1. Data & State (`NoteStore`)
*   We need a way to look up notes by "name".
*   Name matching strategy:
    *   Exact match on **Filename** (minus extension).
    *   Case-insensitive match.
    *   (Optional) Match on **Title** (first line) if filename match fails.
*   **Action**: Add `findNote(byTitleOrPath: String) -> NoteFile?` to `NoteStore`.

### 2. Editor Integration (`PlainTextEditor`)
*   **Attributes**:
    *   Use `NSTextView` text storage attributes to colorize `[[...]]`.
    *   We need to know which links are valid vs invalid to apply Blue vs Orange color.
    *   *Problem*: `PlainTextEditor` doesn't know about `NoteStore`.
    *   *Solution*: Pass a `validateLink: (String) -> Bool` closure to `PlainTextEditor`.
*   **Auto-complete**:
    *   Implement `textView(_:completions:forPartialWordRange:indexOfSelectedItem:)`.
    *   Trigger completion when `[[` is detected or inside brackets.
    *   Pass `getLinkSuggestions: (String) -> [String]` closure to `PlainTextEditor`.
*   **Click Handling**:
    *   Use `NSLinkAttributeName` with a custom scheme `neonv-note://<name>`.
    *   Or handle `textView:clickedOnLink:at:`.
    *   Pass `onOpenLink: (String) -> Void` closure.

### 3. Preview Integration (`MarkdownPreviewView`)
*   **Parsing**:
    *   Update `processInlineFormatting` to detect `\[\[(.*?)\]\]`.
    *   Render as `NSLinkAttributeName`.
*   **Validation**:
    *   Need validation logic here too to style (Blue/Orange) if we want to show broken links in preview. (Spec says "Visual styling shows...").
    *   Pass `validateLink` closure.

### 4. Implementation Steps

#### Step 1: NoteStore Extensions
*   Add method to resolve a link string to a `NoteFile`.
*   Add method to get list of potential link targets (for autocomplete).

#### Step 2: Editor Syntax Highlighting
*   Modify `PlainTextEditor.swift` `applySearchHighlighting` -> `updateAttributes`.
*   Scan for `\[\[(.*?)\]\]`.
*   Check validity using callback.
*   Apply Blue or Orange color.
*   Apply `NSLinkAttributeName` (or custom attribute).

#### Step 3: Editor Click Handling
*   Implement delegate method for link clicks.
*   Trigger `onOpenLink`.

#### Step 4: Editor Auto-complete
*   Implement `NSTextViewDelegate.textView(_:completions:...)`.
*   Trigger `complete(_:)` programmatically in `textDidChange` if `[[` just typed? Or rely on user pressing F5/Esc?
*   *UX Decision*: Try to make it auto-trigger if possible, but standard macOS text view behavior usually requires explicit trigger. We can try `complete(nil)` in `textDidChange`.

#### Step 5: Markdown Preview Support
*   Update parser in `MarkdownPreviewView`.
*   Apply similar styling and link handling.

#### Step 6: Navigation Logic (ContentView)
*   Wire up the closures in `ContentView` (or wherever these views are instantiated).
*   Implement "Open or Create" logic.

## Questions/Risks
*   **Performance**: Scanning all text for `[[...]]` and validating against 1000s of files on every keystroke (`updateNSView`) might be slow.
    *   *Mitigation*: Debounce or optimize. `PlainTextEditor.updateNSView` is called often. We should only re-parse if text changed.
*   **Auto-complete**: `NSTextView` completion UI is standard but might feel dated.
*   **Link Validation**: Requires `NoteStore` access in `updateNSView`.

## Refined Plan

1.  **Update `NoteStore`**: Add lookup and suggestion methods.
2.  **Update `PlainTextEditor`**:
    *   Add `linkValidator: (String) -> Bool`
    *   Add `onOpenLink: (String) -> Void`
    *   Add `linkSuggestions: (String) -> [String]`
    *   Implement highlighting loop.
    *   Implement `NSTextViewDelegate` methods.
3.  **Update `MarkdownPreviewView`**:
    *   Add similar closures.
    *   Update parser.
4.  **Update `ContentView`**:
    *   Pass the closures.
    *   Implement the coordinator actions.
