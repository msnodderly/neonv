# NeoNV UX Performance Autoresearch

## Goal

Minimize the wall-clock time for the **full edit workflow**:
search for a note → select it → open editor → make an edit → autosave completes.

## Metric

Average seconds reported by `testFullEditWorkflowPerformance` (XCTest `measure` block).
Printed by `./autoresearch.sh`. **Lower is better.**

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

```bash
# Get current benchmark time
./autoresearch.sh

# Verify build + lint are clean
./autoresearch.checks.sh

# Run all UI tests (functional + benchmark)
cd NeoNV && xcodebuild test \
  -scheme NeoNV \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

## Installing pi-autoresearch

```bash
pi install https://github.com/davebcn87/pi-autoresearch
```

Then run `/autoresearch` in pi to start the autonomous optimization loop.
