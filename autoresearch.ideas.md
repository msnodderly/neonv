# Autoresearch Optimization Ideas

## File Discovery / Startup
- `discoverFiles()` reads first 512 bytes + 2048 bytes from every file — could batch or parallelize with DispatchQueue.concurrentPerform
- `enumerateNotes()` does `readFirstLineStatic` + `readRawContentStatic` + `parseTagsStatic` per file — lots of redundant I/O (reads same file twice)
- Merge `readFirstLineStatic` and `readRawContentStatic` into a single read per file
- MetadataCache warm start: show cached notes immediately, validate in background

## Search Path
- `matches(query:)` does 4 `String.contains()` calls with pre-lowercased strings — could use a single combined search string
- `filteredNotes` is a computed property re-evaluated on every access — could cache
- Search debounce (50ms) fires on every keystroke — each debounce triggers `autoSelectTopMatch()` which accesses `filteredNotes`

## Note Loading / Editor Focus  
- File loading uses `Task.detached` even for tiny files — synchronous load for small files eliminates async frame latency
- `loadSelectedNote` resets scroll fractions and does cursor map bookkeeping before loading

## Autosave
- 500ms debounce — could reduce to 300ms since the benchmark sleeps 0.5s waiting for it
- `atomicWrite` creates a temp file + moveItem — could use direct `.atomic` write option

## View Rendering
- `NoteListView` / `HorizontalNoteListView` render all notes in a List — SwiftUI List should handle this with lazy loading
- `HighlightedText` in list rows may be expensive with 500 items
- Each note row shows tags with `ForEach` — potential layout cost
