# NeoNV UX Performance Autoresearch

## Goal

Minimize the wall-clock time for the **full file-list scroll workflow**:
open the note list at the top → scroll through the entire list → reach the last visible note.

## Metric

Average seconds reported by `testFullFileListScrollPerformance` (XCTest `measure` block).
Printed by `./autoresearch.sh`. **Lower is better.**

## What Is (and Isn't) Measured

The benchmark measures **pure runtime list-scrolling performance only** — the time the user
experiences inside the already-running app while traversing the file list.

**Build time is explicitly excluded.** The app must be compiled before the
benchmark starts. `autoresearch.sh` uses `xcodebuild test-without-building` so
that the compiler never runs during a timed iteration.

## Baseline

Run `./autoresearch.sh` once on an unmodified build to establish the baseline.
Record the result here after the first run.

## Optimization Targets

The following areas are most likely to affect the benchmark:

| File | Potential improvement |
|------|-----------------------|
| `NeoNV/NeoNV/ContentView.swift` | List filtering and note-list selection churn |
| `NeoNV/NeoNV/HorizontalNoteListView.swift` | Row layout cost while scrolling |
| `NeoNV/NeoNV/HighlightedText.swift` | Highlight rendering cost in list rows |
| `NeoNV/NeoNV/NoteStore.swift` | Note metadata size / search preview work that inflates row rendering |

## Running Manually

**Always build before benchmarking** — the benchmark uses `test-without-building`
so build time never pollutes the metric.

The UI benchmark generates its 500-note fixture set with
`scripts/generate-test-fixtures.sh`; the fixture files are not checked in.
`autoresearch.sh` creates a temporary fixture directory inside NeoNV's app
container and removes it when the benchmark exits.

```bash
# Step 1: compile + lint (must pass before benchmarking)
./autoresearch.checks.sh

# Step 2: benchmark (no build, pure runtime measurement)
./autoresearch.sh
```

To generate the same fixture set manually:

```bash
scripts/generate-test-fixtures.sh
```

That default writes to `~/Library/Containers/net.area51a.NeoNV/Data/tmp/NeoNVUITests-Fixtures`,
which is the fallback path used by the UI tests when `NEONV_TEST_NOTES_DIR` is not set.
