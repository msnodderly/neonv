# Plan: Wiki Links (Obsidian-like Core + Alias) - Implemented Snapshot

## Summary
Wiki links are implemented with plain-text syntax (`[[target]]`, `[[target|label]]`) across editor and preview, plus open/create/ambiguity flows.  
Performance recovery was completed using an in-memory index only (no database, no on-disk index).

## Implemented Scope
- Syntax: `[[target]]` and `[[target|label]]`
- Resolution: filename/path based, case-insensitive, no first-line-title fallback
- Missing links: create confirmation dialog, then create + open on confirm
- Ambiguous basenames: picker dialog of matching note paths
- Editor navigation: Cmd-click opens wiki targets
- Preview navigation: click opens wiki targets
- Out of scope: heading/block targets (`#heading`, `^block`), backlinks pane, link rewrite on rename

## Implemented Files
- Added: `NeoNV/NeoNV/WikiLinkSupport.swift`
- Updated: `NeoNV/NeoNV/NoteStore.swift`
- Updated: `NeoNV/NeoNV/ContentView.swift`
- Updated: `NeoNV/NeoNV/PlainTextEditor.swift`
- Updated: `NeoNV/NeoNV/MarkdownPreviewView.swift`
- Updated: `NeoNV/NeoNV/OrgPreviewView.swift`
- Updated: `NeoNV/NeoNV/AppSettings.swift`
- Updated: `NeoNV/NeoNV/SettingsView.swift`

## Shipped APIs / Types
- `WikiLinkResolution` (`resolved`, `missing`, `ambiguous`)
- `WikiLinkSuggestion` (`insertTarget`, `display`, `detailPath`)
- `WikiLinkMatch` parser output
- `NoteStore.resolveWikiLink(_:)`
- `NoteStore.wikiLinkSuggestions(prefix:limit:)`
- `NoteStore.canonicalWikiTarget(for:)`
- `NoteStore.wikiIndexVersion` (published invalidation token)

## Final Behavior (Actual)
1. Canonical targets are basename-based when unique, path-based when duplicate basename exists.
2. Targets with `/` resolve against relative path without extension.
3. Editor link styling: resolved = blue, missing/ambiguous = orange.
4. Cmd-click in editor opens wiki target through resolver flow.
5. Markdown and org previews open internal wiki links; HTTP/HTTPS links remain external.
6. Autocomplete is tab-first inside `[[...]]` target context.
7. `Tab` completes unique/exact matches.
8. If multiple candidates remain, `Tab` opens suggestion list instead of auto-inserting.
9. `Down Arrow` can open suggestions on demand.
10. `Enter` or `Tab` commits dropdown selection; `Esc` dismisses.
11. Autocomplete can be disabled in Settings (`Wiki Link Autocomplete`) while keeping parsing/open/create behavior.

## Performance Recovery (No DB)
- Removed hot-path global recomputation from editor update cycle.
- Added fast short-circuit for styling when text does not contain `[[`.
- Moved resolver/suggestion work to cached in-memory indexes in `NoteStore`.
- Rebuild index on `notes` mutations and bump `wikiIndexVersion`.
- Reused `NoteFile.matches(query:)` (same matching path as Cmd-L search) for suggestion candidate generation.

## Validation Checklist (Current)
1. Build: `xcodebuild -scheme NeoNV -destination 'platform=macOS' build`
2. Editor Cmd-click opens resolved wiki links.
3. Missing wiki links show create confirmation, then create/open.
4. Ambiguous wiki links show picker and open selected note.
5. Preview links open internal wiki notes; external URLs still open externally.
6. Tab completion works inside `[[...]]` with explicit commit/cancel behavior.
7. Keyboard interactions remain beep-free around editor/preview completion flows.
