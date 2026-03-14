# NeoNV UX Performance Autoresearch

## Goal

Minimize the wall-clock time for the **full edit workflow**:
search for a note → select it → open editor → make an edit → autosave completes.

## Metric

Average seconds reported by `testFullEditWorkflowPerformance` (XCTest `measure` block).
Printed by `./autoresearch.sh`. **Lower is better.**

## What Is (and Isn't) Measured

The benchmark measures **pure runtime UX performance only** — the time the user
experiences inside the already-running app:

> search for a note → select it → editor opens → edit made → autosave completes

**Build time is explicitly excluded.** The app must be compiled before the
benchmark starts. `autoresearch.sh` uses `xcodebuild test-without-building` so
that the compiler never runs during a timed iteration. This means:

- Compile time, linker time, and DerivedData warming are **not** optimization targets.
- Every candidate change must be compiled first via `autoresearch.checks.sh`
  (which calls `build-for-testing`) before `autoresearch.sh` runs.
- Do **not** optimize for faster incremental builds — only for faster in-app
  interactions visible to the user at runtime.

## Baseline

Run `./autoresearch.sh` once on an unmodified build to establish the baseline.
Record the result here after the first run.

## Optimization Targets

The following areas are most likely to affect the benchmark:

| File | Potential improvement |
|------|-----------------------|
| `NeoNV/NeoNV/ContentView.swift` | Search debounce interval (currently 50 ms) |
| `NeoNV/NeoNV/NoteStore.swift` | `NoteFile.matches(query:)` filtering algorithm |
| `NeoNV/NeoNV/NoteStore.swift` | `discoverFiles()` — metadata loading concurrency |
| `NeoNV/NeoNV/PlainTextEditor.swift` | First-responder / focus time after note selection |
| `NeoNV/NeoNV/HorizontalNoteListView.swift` | List rendering performance |

## Running Manually

**Always build before benchmarking** — the benchmark uses `test-without-building`
so build time never pollutes the metric.

```bash
# Step 1: compile + lint (must pass before benchmarking)
./autoresearch.checks.sh

# Step 2: benchmark (no build, pure runtime measurement)
./autoresearch.sh

# Run the full test suite (functional + benchmark) without building
cd NeoNV && xcodebuild test-without-building \
  -scheme NeoNV \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```

## Installing pi-autoresearch

```bash
pi install https://github.com/davebcn87/pi-autoresearch
```

Then run `/autoresearch` in pi to start the autonomous optimization loop.
