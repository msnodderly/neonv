# UI Test Pass — June 11, 2026

Full exercise of the UI via XCUITest automation (screenshots audited for every
step), plus fixes landed during the pass. Companion artifacts: the new tests in
`NeoNV/NeoNVUITests/NeoNVUITests.swift`.

## How to test the UI (working recipe)

```bash
# 1. Generate fixtures (500 numbered notes + snippet-probe.md)
scripts/generate-test-fixtures.sh /tmp/neonv-uitest-fixtures 500

# 2. Build app + test bundles
cd NeoNV && xcodebuild build-for-testing -scheme NeoNV \
  -destination 'platform=macOS' -derivedDataPath ../.build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO

# 3. Run UI tests (note the TEST_RUNNER_ prefix — required for the env var
#    to reach the UI test runner; the bare variable alone never arrives)
TEST_RUNNER_NEONV_TEST_NOTES_DIR=/tmp/neonv-uitest-fixtures \
  xcodebuild test-without-building -scheme NeoNV -destination 'platform=macOS' \
  -derivedDataPath ../.build -resultBundlePath /tmp/neonv.xcresult \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO

# 4. Pull screenshots/UI hierarchies out of the result bundle
xcrun xcresulttool export attachments --path /tmp/neonv.xcresult --output-path /tmp/out
```

Perf benchmark: `./autoresearch.checks.sh && ./autoresearch.sh` (see
`autoresearch.md`).

Hard-won lessons encoded in the tests:

- `-ApplePersistenceIgnoreState YES` launch argument is required, or window/
  state restoration from a previous manual session pollutes what you measure.
- SwiftUI list texts expose content through the AX **value**, not the label —
  predicates must use `value`.
- `app.buttons["Rename"]` can match a **Touch Bar** suggestion; prefer keyboard
  confirmation (Return) or scope queries to the dialog.
- Rows outside the visible scroll region report `exists == true` but are not
  hittable — narrow via search before clicking a specific row.
- The failure-time "App UI hierarchy" attachment in the result bundle is the
  fastest way to see what the app actually showed.

## What was exercised (all passing)

| Surface | Test |
|---|---|
| List scrolling, 500 notes | `testScrollFileListWorkflow`, perf benchmark |
| Select note → editor loads | `testSelectingNoteLoadsEditorContent` |
| Search → Return opens top match | `testSearchReturnOpensTopPartialMatch` |
| Cmd-N create + type | `testCreateNewNoteWorkflow` |
| Search narrowing (non-matches removed) | `testSearchNarrowsListToMatches` |
| Body-match snippet recentering | `testBodyMatchShowsRecenteredSnippet` |
| Default 25% list pane | `testListPaneDefaultWidthIsQuarterOfWindow` |
| Preview, find bar, layout toggle, search-bar hide/show, keyboard flow search→list→editor, nav history, context-menu rename, shortcuts sheet | `testExerciseCoreSurfaces` (screenshot per step) |

## Bugs found and fixed in this pass

1. **CLI folder argument dead under App Sandbox.** The feature existed
   (neonv-npg) but the sandbox denied reading any folder not granted through
   the open panel — launch with a path did nothing. Removed the sandbox
   entitlement (app ships via Homebrew/GitHub, not MAS; docs always treated
   sandboxing as a future MAS concern). Added one-time migration of the old
   container preferences so existing users keep their folder + settings.
2. **Invalid-path alert silently dropped.** `setFolder` showed its NSAlert
   during app init, before the run loop existed. Now deferred until the app
   runs, and the app activates itself for CLI launches.
3. **Symlinked folder paths mangled.** `/tmp/notes` (→ `/private/tmp/notes`)
   produced relative paths like `/privatenote-0500.md` in every row. Cause:
   prefix string-replacement against the unresolved folder path. Fixed with
   `realpath(3)` canonicalization (`URL.resolvingSymlinksInPath()` is *not*
   equivalent — it strips `/private` back off).
4. **Search results that look wrong (the "narrowing" complaint).** Narrowing
   itself worked, but a note matching deep in its body showed only the head of
   the file in the row preview — indistinguishable from a non-match. Row
   previews now recenter on the first body match (`…` prefix) and highlight it.
5. **Nondeterministic list order** for notes sharing a modification date
   (unstable sort). Now ties break by path.
6. **`autoresearch.sh` env var never reached the UI test runner** (needs the
   `TEST_RUNNER_` prefix). The benchmark only worked when stale fixtures
   happened to exist at the default container path.
7. **HSplitView can't express a default pane width** — it derives the divider
   from content's natural size and ignores `idealWidth` (measured: always
   551pt regardless of settings). Replaced with a custom splitter: 25% default,
   drag clamped to the same 180–800pt bounds, resize cursor on hover.
8. **Opening a fresh folder (no metadata cache) showed an empty list forever**
   even though discovery found every note. `@Published` emits on `willSet`, and
   `.onReceive(noteStore.$notes) { _ in rebuildFilteredNotes() }` re-read
   `noteStore.notes` — still the old empty array — instead of the received
   value. With a cache there are two publishes and the second rebuild reads the
   first's data, which is why normal use masked it. The filter now consumes the
   received array. (This, not app slowness, was behind the benchmark's
   "list never populated" timeouts: autoresearch always uses a fresh mktemp
   fixtures dir.)
9. **The perf benchmark itself couldn't run on current Xcode** — explicit
   `startMeasuring`/`stopMeasuring` now require
   `XCTMeasureOptions.invocationOptions = [.manuallyStart, .manuallyStop]`.

## Friction points and open issues

- **Selection lost from view after clearing search.** ✅ *Addressed 2026-06-12:*
  clearing the search now recenters the restored selection via
  `ScrollViewReader` in both list views (`testClearingSearchRevealsSelection`).
  Nav-history/wiki jumps still don't reveal (deliberately out of scope).
- **Search only sees the first 2 KB of each file.** ✅ *Addressed 2026-06-12:*
  full-content index capped at 256 KB/file (`NoteStore.searchIndexMaxBytes`),
  original case kept for deep-match snippets; not persisted to the metadata
  cache, so cache-warmed notes match on previews for ~the first second after
  cold launch until discovery refreshes them
  (`testSearchFindsMatchBeyondPreviewCap`).
- **Multi-word search is phrase-only.** ✅ *Addressed 2026-06-12:* AND-of-terms
  via `NoteFile.searchTerms(from:)` + `matches(allLowercasedTerms:)`; wiki
  suggestions use the same rule; each term highlights independently
  (`testMultiWordSearchRequiresAllTerms`).
- **Toggle File List has no keyboard shortcut.** ✅ *Addressed 2026-06-12:*
  ⌘⇧B, listed in the shortcuts sheet and Help (`testToggleFileListShortcut`).
- **A no-window state can be restored.** ✅ *Addressed 2026-06-12:*
  `applicationShouldTerminateAfterLastWindowClosed = true` — closing the
  window quits, so a windowless state can no longer be saved
  (`testCloseWindowQuitsApp`).
- **Splitter position doesn't persist** across launches (same as before the
  25% change — HSplitView never persisted either). Could store the dragged
  width in `AppSettings` if "sticky" is preferred over "always 25%".
- **First launch after a rebuild was occasionally slow to populate** (>10 s
  once). Most "never populated" cases turned out to be fixed bug #8; if it
  recurs with the fix in place, suspect one-time verification of the freshly
  signed binary.
- **Editor text sits nearly flush against the divider** (~6 px). A 12–16 pt
  horizontal inset would help readability.
- **AX granularity:** all three row texts share the `note-row` identifier;
  distinct `note-title` / `note-path` / `note-preview` identifiers would make
  tests and screen-reader output more precise.
- **Horizontal layout** keeps a ~150 pt list band even with one match — dead
  space; could auto-shrink to fit row count.
- Automation permissions: System Events keystroke injection is not granted to
  the agent environment (osascript "assistive access" denial). XCUITest needs
  no extra permissions and is the sanctioned path — stick with it.
- **(Found 2026-06-12) The drag-based scroll helpers never scroll.** On macOS,
  press-drag inside a List *selects rows*; only wheel events
  (`XCUIElement.scroll(byDeltaX:deltaY:)`) scroll it. The legacy
  `dragUp/dragDownInListPane` loops in `testScrollFileListWorkflow` and
  `testFullFileListScrollPerformance` terminate because `exists` is true even
  for off-screen rows — so the scroll benchmark mostly measures existence
  polling, not scrolling. `scrollListUntilHittable` (wheel-based, hittability-
  checked) is the correct pattern; migrating the benchmark to it would change
  the metric and needs a fresh baseline — left as a deliberate follow-up.

## Performance notes

- Full-list scroll benchmark (`./autoresearch.sh`, 500 notes, 5 iterations):
  **1.240 s average** — recorded as today's baseline in `autoresearch.md`.
- Search keystroke → narrowed list is visually instant in recordings (20 ms
  debounce + single `contains` over precomputed `searchCombined`).
- Real-world folder (742 notes in Dropbox) warm-starts instantly from the
  metadata cache.
- The snippet recentering work runs only for visible rows during active
  searches; scroll benchmark is unaffected (search empty ⇒ identical code path
  to before).

## Recommended next steps, in order of value

Items 1–5 were implemented 2026-06-12 (see ✅ annotations above).

1. ~~Scroll the selected note into view when a search is cleared~~ ✅
2. ~~AND-of-terms multi-word search~~ ✅
3. ~~Full-content search index with size cap~~ ✅
4. ~~Single-window semantics~~ ✅
5. ~~Keyboard shortcut for Toggle File List~~ ✅
6. Editor horizontal inset (skipped per review).
7. Rebuild the scroll benchmark on wheel-event scrolling with a fresh baseline
   (see the "drag-based scroll helpers never scroll" finding).
