# Plan: Wiki Links (Obsidian-like Core + Alias)

## Summary
Implement `[[target]]` and `[[target|label]]` wiki links across editor and preview with Obsidian-like filename/path resolution, Cmd-click open in editor, create-on-missing confirmation, and ambiguity picker.

## Scope
- Syntax: `[[target]]`, `[[target|label]]`
- Resolution: filename/path based only (case-insensitive), no title fallback
- Missing target: prompt to create, then create + open
- Ambiguous basename: show picker of matching relative paths
- Editor open gesture: Cmd-click only
- Rename behavior: no auto-rewrite of existing links
- Out of scope: heading/block targets (`#heading`, `^block`), backlinks pane

## Files
- Add: `NeoNV/NeoNV/WikiLinkSupport.swift`
- Update: `NeoNV/NeoNV/NoteStore.swift`
- Update: `NeoNV/NeoNV/ContentView.swift`
- Update: `NeoNV/NeoNV/PlainTextEditor.swift`
- Update: `NeoNV/NeoNV/MarkdownPreviewView.swift`
- Update: `NeoNV/NeoNV/OrgPreviewView.swift`

## API Additions
- `enum WikiLinkResolution { resolved(NoteFile), missing(String), ambiguous([NoteFile]) }`
- `struct WikiLinkSuggestion { insertTarget, display, detailPath }`
- `struct WikiLinkMatch { fullRange, target, label }`
- `NoteStore.resolveWikiLink(_:)`
- `NoteStore.wikiLinkSuggestions(prefix:limit:)`
- `NoteStore.canonicalWikiTarget(for:)`

## Behavior Rules
1. Unique basename resolves as `[[basename]]`; duplicate basename requires/returns `[[relative/path]]`.
2. Targets containing `/` resolve by exact relative path without extension.
3. Missing target click opens create confirmation.
4. Ambiguous target click opens a picker.
5. Markdown/org external URLs continue opening externally.

## Acceptance Criteria
- `[[...]]` recognized and styled in editor and preview.
- Cmd-click in editor opens resolved wiki link target.
- Preview click opens wiki link target.
- Autocomplete suggestions appear while typing inside `[[...]]` target area.
- Missing target offers create flow; confirm creates and opens new note.
- Ambiguous basename shows chooser and opens selected note.
- Build succeeds: `xcodebuild -scheme NeoNV -destination 'platform=macOS' build`.

## Manual Test Checklist
### Prerequisite
1. Select a notes folder containing at least two files with the same basename in different subfolders.

### Steps
1. Type `[[existing-note]]` in editor and Cmd-click it.
2. Type `[[existing-note|Display Name]]` and Cmd-click display text.
3. Type `[[missing-note]]` and Cmd-click; choose Cancel.
4. Cmd-click same missing link again; choose Create.
5. Type `[[duplicate-basename]]` and Cmd-click.
6. In preview mode, click a wiki link.
7. In preview mode, click a normal markdown/org URL.
8. Type inside `[[pa` and verify completion suggestions.
9. Verify Tab/Shift-Tab/Escape behavior still produces no unwanted beep.

### Expected
1. Resolved links open the correct note.
2. Alias display opens the target note.
3. Cancel does not create a note.
4. Create writes file and opens it.
5. Ambiguous links show a picker with relative paths.
6. Preview click opens internal wiki links.
7. External URLs still open externally.
8. Completion inserts canonical targets.
9. Keyboard navigation remains unchanged and beep-free.
