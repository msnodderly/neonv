# Plan: Fix Strikethrough with @done (neonv-rmw)

## Problem

Strikethrough formatting for `@done` lines only works when switching notes, not when typing `@done` in the editor.

**Root cause:** In `PlainTextEditor.swift`, `applyDoneStrikethrough` is guarded by `if textChanged` (line 104). When the user types, `textDidChange` updates the binding, but by the time `updateNSView` runs, `textView.string` already equals the new text, so `textChanged` is false and strikethrough is never applied.

## Solution

Add a coordinator flag to track when the user has edited text, triggering strikethrough to be reapplied.

## File to Modify

`/Users/mds/src/neonv/NeoNV/NeoNV/PlainTextEditor.swift`

## Changes

### 1. Add flag to Coordinator (line ~221)

```swift
var lastSearchTerms: [String] = []
var needsStrikethroughUpdate: Bool = false  // ADD THIS LINE
```

### 2. Set flag in textDidChange (line ~231)

```swift
func textDidChange(_ notification: Notification) {
    guard let textView = notification.object as? NSTextView else { return }
    text.wrappedValue = textView.string
    cursorPosition.wrappedValue = textView.selectedRange().location
    needsStrikethroughUpdate = true  // ADD THIS LINE
}
```

### 3. Update condition in updateNSView (lines 103-106)

Replace:
```swift
// Only re-apply strikethrough if text changed
if textChanged {
    applyDoneStrikethrough(to: textView)
}
```

With:
```swift
// Only re-apply strikethrough if text changed or user edited text
if textChanged || context.coordinator.needsStrikethroughUpdate {
    applyDoneStrikethrough(to: textView)
    context.coordinator.needsStrikethroughUpdate = false
}
```

## Verification

1. Run `./run.sh` to build and launch NeoNV
2. Open a note with existing `@done` tags - verify strikethrough displays
3. Type `@done` at the end of a line - verify strikethrough applies immediately
4. Remove `@done` from a line - verify strikethrough is removed
5. Test `- [x]` checkbox syntax - verify strikethrough works
6. Switch between notes - verify strikethrough persists correctly
