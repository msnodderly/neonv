# Plan: MVP-007 - Save Failure Handling (Loud Errors)

## Overview

This plan covers implementing robust error handling for auto-save failures in neonv. Data integrity is the highest priority; the user must never be allowed to unknowingly lose data. When a save fails, the app must "scream loudly" (modal alert) and block further editing until the situation is resolved.

**Issues Addressed:**
- MVP-007: Save Failure Handling (Loud Errors)

**Priority:** P0 (Critical)

---

## Current State

In `ContentView.swift`:
- `performSave()` calls `atomicWrite()`.
- If `atomicWrite()` throws, the error is caught and printed to the console (`print("Save failed: \(error)")`).
- No UI feedback is provided to the user.
- `isDirty` remains true, but the user can continue editing.

---

## Target Behavior

### Save Failure Alert

When auto-save fails, a modal alert appears showing:
- **Title:** "Save Failed"
- **Message:** The file path and the specific error description (e.g., "Disk Full", "Permission Denied").
- **Recovery Options:**
  - **Retry:** Attempts the save again.
  - **Save As...:** Opens a save panel to choose a new location.
  - **Copy to Clipboard:** Copies the current editor content so it can be pasted elsewhere.
  - **Show in Finder:** Opens the parent folder in Finder to help diagnose permission/disk issues.
  - **Discard Changes:** (Danger) Explicitly abandon unsaved work.

### Blocking State

While the alert is visible:
- Further editing in the `EditorView` should be disabled or blocked.
- Navigation to other notes should be disabled to prevent losing the current buffer.

### App Quit Warning

- If the app has unsaved changes (especially after a save failure), attempting to quit should prompt the user with a warning.

---

## Implementation Plan

### Phase 1: Error State Infrastructure

**File:** `ContentView.swift`

1. Add state to track save errors:
```swift
struct SaveError: Identifiable {
    let id = UUID()
    let url: URL
    let error: Error
}

@State private var lastSaveError: SaveError?
```

2. Update `performSave()` to capture the error:
```swift
    private func performSave() async {
        // ... existing guards ...
        do {
            try await atomicWrite(content: content, to: note.url)
            await MainActor.run {
                isDirty = false
                lastSaveError = nil // Clear any previous error
            }
        } catch {
            await MainActor.run {
                lastSaveError = SaveError(url: note.url, error: error)
            }
        }
    }
```

### Phase 2: Modal Alert UI

**File:** `ContentView.swift`

1. Add an `.alert` modifier to the main view:
```swift
.alert(item: $lastSaveError) { saveError in
    Alert(
        title: Text("Save Failed"),
        message: Text("Could not save to \(saveError.url.lastPathComponent):\n\n\(saveError.error.localizedDescription)"),
        primaryButton: .default(Text("Retry")) {
            Task { await performSave() }
        },
        secondaryButton: .cancel(Text("Cancel"))
    )
}
```
*Note: The standard SwiftUI `Alert` is limited. We might need a custom modal or `NSAlert` for more complex recovery options.*

2. Custom Recovery Alert (using `NSAlert` for better control):
```swift
    private func showSaveErrorAlert(saveError: SaveError) {
        let alert = NSAlert()
        alert.messageText = "Save Failed"
        alert.informativeText = "Could not save to \(saveError.url.lastPathComponent).\n\nError: \(saveError.error.localizedDescription)"
        alert.alertStyle = .critical
        
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Save As...")
        alert.addButton(withTitle: "Copy to Clipboard")
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Discard Changes")
        
        let response = alert.runModal()
        // Handle response...
    }
```

### Phase 3: Recovery Logic

1. **Retry:** Just call `performSave()` again.
2. **Save As...:** Use `NSSavePanel`.
3. **Copy to Clipboard:** `NSPasteboard.general.clearContents()` and `setString()`.
4. **Show in Finder:** `NSWorkspace.shared.activateFileViewerSelecting([url])`.
5. **Discard Changes:** Set `isDirty = false`, `lastSaveError = nil`.

### Phase 4: Blocking Interaction

1. Disable editor when `lastSaveError != nil`.
2. Disable list selection when `lastSaveError != nil`.

### Phase 5: Quit Warning

Update `NeoNVApp.swift` or `ContentView` to handle window closing/quit events when `isDirty` is true.

---

## Testing Plan

### Manual Testing Scenarios

1. **Permission Denied:**
   - `chmod 444` a note file while editing it.
   - Verify alert appears.
   - Verify "Retry" fails again (alert reappears).
   - Verify "Copy to Clipboard" works.

2. **File Deleted:**
   - Delete the file from Finder while editing in NeoNV.
   - Verify how `atomicWrite` handles this (it should recreate it if folder is writable).

3. **Read-Only Folder:**
   - `chmod 555` the notes folder.
   - Verify alert appears.

4. **Recovery Verification:**
   - Test each button in the alert and verify expected outcome.

---

## Definition of Done

- [ ] Save failures trigger a modal alert.
- [ ] Alert displays clear error information and file path.
- [ ] User can retry, save elsewhere, or copy content from the alert.
- [ ] Editing is blocked while a save error is active.
- [ ] App cannot be closed with unsaved changes without a warning.
- [ ] Code follows project conventions and compiles without errors.
