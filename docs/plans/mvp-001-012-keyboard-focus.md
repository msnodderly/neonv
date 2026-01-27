# Plan: MVP-001 & MVP-012 - Focus Management and Keyboard Navigation

## Overview

This plan covers implementing proper focus management and keyboard navigation for neonv. These two issues are tightly coupled since both rely on `@FocusState` and custom key handling.

**Issues Addressed:**
- MVP-001: Basic Window with Three-Pane Layout (remaining: search focus on launch)
- MVP-012: Basic Keyboard Navigation (Tab Cycling)

**Priority:** P0 (Critical - "Every beep is a bug")

---

## Current State

The existing `ContentView.swift` has:
- Basic three-pane layout with `NavigationSplitView`
- `TextField` for search
- `List` for notes
- `TextEditor` for content
- No focus management
- No custom keyboard handling

---

## Target Behavior

### Focus States

```
┌─────────────────────────────────────────────┐
│ [Search box] ← FOCUSED ON LAUNCH     [P]    │
├──────────────┬──────────────────────────────┤
│ Note List    │ Editor Pane                  │
│              │                              │
└──────────────┴──────────────────────────────┘
```

### Focus Cycle

```
Search ──Tab/↓──> List ──Tab──> Editor
   ^                              │
   └────Shift-Tab────Shift-Tab───┘
```

### Key Mappings

| Context | Key | Action | Notes |
|---------|-----|--------|-------|
| Search | Tab | Select first note, focus list | If list not empty |
| Search | Down Arrow | Select first note, focus list | Same as Tab |
| Search | Up Arrow | Do nothing | NO BEEP |
| Search | Enter | Create new note OR select match | Based on search results |
| List | Tab | Focus editor | |
| List | Shift-Tab | Focus search | |
| List | Up Arrow | Navigate up OR return to search | If at top, go to search |
| List | Down Arrow | Navigate down | Default List behavior |
| List | Right Arrow | Focus editor | Same as Enter |
| List | Enter | Focus editor | |
| Editor | Shift-Tab | Focus list | Keep selection |
| Editor | Tab | Insert tab character | Normal editor behavior |

---

## Implementation Plan

### Phase 1: Focus State Infrastructure

**File:** `ContentView.swift`

1. Create focus enum:
```swift
enum FocusedField: Hashable {
    case search
    case noteList
    case editor
}
```

2. Add `@FocusState` property:
```swift
@FocusState private var focusedField: FocusedField?
```

3. Apply `.focused()` modifier to each component:
   - Search TextField: `.focused($focusedField, equals: .search)`
   - Note List: `.focused($focusedField, equals: .noteList)`
   - TextEditor: `.focused($focusedField, equals: .editor)`

4. Focus search on appear:
```swift
.onAppear {
    focusedField = .search
}
```

**Success Criteria:**
- [x] App launches with cursor in search box
- [x] User can immediately start typing

### Phase 2: Custom Key Handling

**File:** `ContentView.swift`

1. Add `.onKeyPress()` handlers to each focusable component

2. Search box key handling:
```swift
.onKeyPress { press in
    if press.key == .tab && !press.modifiers.contains(.shift) {
        // Move to list, select first note if available
        if !filteredNotes.isEmpty {
            selectedNote = filteredNotes.first
        }
        focusedField = .noteList
        return .handled
    }
    if press.key == .downArrow {
        // Same behavior as Tab
        if !filteredNotes.isEmpty {
            selectedNote = filteredNotes.first
        }
        focusedField = .noteList
        return .handled
    }
    if press.key == .upArrow {
        // Do nothing, but don't beep
        return .handled
    }
    return .ignored
}
```

3. Note list key handling:
```swift
.onKeyPress { press in
    if press.key == .tab && !press.modifiers.contains(.shift) {
        focusedField = .editor
        return .handled
    }
    if press.key == .tab && press.modifiers.contains(.shift) {
        focusedField = .search
        return .handled
    }
    if press.key == .return {
        focusedField = .editor
        return .handled
    }
    return .ignored
}
```

4. Editor key handling (Shift-Tab only, Tab inserts tab):
```swift
.onKeyPress(.tab, modifiers: .shift) { _ in
    focusedField = .noteList
    return .handled
}
```

**Success Criteria:**
- [x] Tab from search moves to list (selects first note)
- [x] Down arrow from search moves to list
- [x] Up arrow in search does NOT beep
- [x] Tab from list moves to editor
- [x] Shift-Tab from list moves to search
- [x] Shift-Tab from editor moves to list
- [x] Tab in editor inserts tab character
- [x] Enter in list moves to editor

### Phase 3: List Focus Handling (Technical Challenge)

SwiftUI `List` doesn't natively accept keyboard focus well. Options:

**Option A: Focusable wrapper (Recommended)**
- Wrap List in a focusable container
- Use `.focusable()` modifier on the wrapper
- Handle key events on wrapper

**Option B: NSViewRepresentable**
- Use AppKit `NSTableView` for better focus control
- More complex but more native behavior

**Decision:** Start with Option A. If focus doesn't work well, escalate to Option B.

Implementation for Option A:
```swift
// Wrap the list
VStack {
    List(filteredNotes, id: \.self, selection: $selectedNote) { note in
        NoteRow(note: note)
    }
}
.focusable()
.focused($focusedField, equals: .noteList)
.onKeyPress { press in
    // Handle navigation keys
}
```

**Success Criteria:**
- [ ] List visually indicates when focused (selection highlight)
- [ ] Up/Down arrows navigate notes when list focused
- [ ] Tab/Shift-Tab work from list

---

## Testing Plan

### Manual Testing Checklist

1. **Launch Test:**
   - [ ] Launch app
   - [ ] Verify cursor is in search box
   - [ ] Type text - verify it appears in search

2. **Tab Navigation Test:**
   - [ ] Press Tab from search → list should focus, first note selected
   - [ ] Press Tab from list → editor should focus
   - [ ] Press Shift-Tab from editor → list should focus
   - [ ] Press Shift-Tab from list → search should focus

3. **Arrow Key Test:**
   - [ ] Down arrow in search → moves to list
   - [ ] Up arrow in search → stays in search, NO BEEP
   - [ ] Up/Down in list → navigates notes

4. **Enter Key Test:**
   - [ ] Enter in list → focuses editor

5. **No Beep Audit:**
   - [ ] Test all navigation keys in all contexts
   - [ ] Document any beeps encountered

### Build Verification

```bash
cd neonv && swift build
```

---


## Estimated Complexity

- Phase 1: Low - Standard SwiftUI patterns
- Phase 2: Medium - Key handling edge cases
- Phase 3: Medium-High - List focus may require iteration

---

## Definition of Done

- [ ] App launches with search focused
- [ ] Full Tab cycle works: Search → List → Editor → (Shift-Tab) → List → Search
- [ ] Down arrow from search selects first note and moves to list
- [ ] No system beeps during normal navigation
- [ ] Code compiles without warnings
- [ ] Manual testing checklist passes
