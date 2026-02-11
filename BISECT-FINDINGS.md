# Bisect Findings: Tab Focus Regression

**Date:** 2026-02-10
**Range tested:** `v0.11.0` (good) → `v0.12.0` (bad)
**Bisect steps:** 5
**First bad commit:** `6bd4530` — "fix: Preserve undo history across preview toggles"

---

## Offending Commit

```
commit 6bd4530c31840f8813a91a03e9269a3d83e57005
Author: Matt S. <mds@area51a.net>
Date:   Sat Feb 7 18:19:43 2026 -0800

    fix: Preserve undo history across preview toggles
```

**PR/Thread:** https://ampcode.com/threads/T-019c3b0a-8431-70ea-8daa-4027ead700b2
**File changed:** `NeoNV/NeoNV/ContentView.swift` (+15, -8)

---

## What Changed

The commit modified `editorOrPreviewPane` in `ContentView.swift`. Previously, the editor and preview were mutually exclusive branches of an `if/else`:

```swift
// BEFORE (v0.11.0) — editor removed from view hierarchy when preview is shown
} else if showPreview {
    previewPane
} else {
    EditorView(...)
        .frame(minWidth: 300)
}
```

After the commit, both views are always mounted in a `ZStack`, with the editor hidden via opacity:

```swift
// AFTER (6bd4530) — editor stays mounted, hidden with opacity(0)
} else {
    ZStack {
        EditorView(...)
            .opacity(showPreview ? 0 : 1)
            .allowsHitTesting(!showPreview)
            .accessibilityHidden(showPreview)

        if showPreview {
            previewPane
        }
    }
    .frame(minWidth: 300)
}
```

---

## Root Cause Diagnosis

The intent was to preserve the `NSUndoManager` history by keeping `EditorView` (and its underlying `NSTextView`) alive across preview toggles. However, this introduced a tab-focus regression:

1. **`EditorView` wraps an `NSTextView` via `NSViewRepresentable`.** The `NSTextView` remains in the window's view hierarchy and participates in the **AppKit responder chain** even when invisible.

2. **`allowsHitTesting(false)` only blocks mouse events**, not keyboard focus. SwiftUI's focus system (and AppKit's key view loop) still considers the hidden `NSTextView` a valid focus target.

3. **`.accessibilityHidden(true)` hides the view from VoiceOver** but does not remove it from keyboard focus navigation.

4. **Result:** When the user presses Tab or Shift-Tab to cycle focus between panes, focus can land on the invisible `EditorView`'s `NSTextView`. The keypress appears to be swallowed — nothing visible happens, and the user may hear a beep or experience a "dead" Tab press.

---

## Suggested Fix Direction

The fix needs to keep `EditorView` mounted (to preserve undo history) while preventing its `NSTextView` from participating in focus navigation when preview is active. Possible approaches:

1. **Disable the `NSTextView` as a first responder when hidden.** Override `acceptsFirstResponder` in the custom `NSTextView` subclass to return `false` when preview mode is active.

2. **Remove the view from the key view loop.** Set `nextKeyView = nil` or use `refusesFirstResponder = true` on the `NSTextView` when the preview is shown.

3. **Use `.focusable(false)` or `.disabled(true)` on the SwiftUI side** when `showPreview` is true, though this may have side effects on the editor's state.

Option 1 is the most targeted — it prevents focus landing on the hidden editor without removing it from the view hierarchy or disrupting its undo manager.
