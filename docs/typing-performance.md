# Long-note typing latency

Investigated on 2026-10-19; fix branch: `fix/long-note-typing-latency`.

## Findings

- Wiki completion searched from the cursor back to the start of the document on
  every text-change and selection-change callback, even during ordinary typing.
  An unclosed target also searched the entire remaining document for `]]`.
- Swift comparisons between AppKit's UTF-16 strings and native UTF-8 strings
  were especially expensive for long notes containing non-ASCII text. The same
  bridged snapshot flowed into SwiftUI change detection and autosave comparisons.
- Every representable update normalized line endings across the entire note,
  including updates caused by cursor movement and scrolling.
- Every character rebuilt the filtered file list to mark an already-dirty note.

The completion lookup now stays within the current line and skips work when
completion is disabled or text is selected. Editor snapshots use Foundation's
bulk UTF-8 encoder, then a native Swift string. The coordinator remembers the
last synchronized binding so local edits do not trigger document comparisons or
normalization. File-list dirty markers rebuild only when a note first gets dirty.

## Measurements

A standalone Debug AppKit harness invoked `textDidChange` and
`textViewDidChangeSelection` together, with the caret at the end of repeated
48-character lines containing an emoji. These are callback timings, excluding
SwiftUI rendering, layout, file I/O, and event delivery; they are not full
keystroke latency measurements.

| Lines | Before | After |
| --- | ---: | ---: |
| 1,000 | 4.64 ms | 0.18 ms |
| 10,000 | 27.32 ms | 1.68 ms |
| 50,000 | 130.07 ms | 8.74 ms |

The isolated completion lookup in the 50,000-line native-string fixture dropped
from about 83 ms to below 0.01 ms. The original session's progressive slowdown
was not profiled directly; these measurements demonstrate reproducible costs
that grow with note length. Extremely long single lines still require scanning
that line, and publishing an edited note still requires a document snapshot.

## Regression checks

`EditorTypingTests.swift` covers target/label ranges, Unicode offsets, line
boundaries, preserving text after unclosed links, snapshot independence, and
long-note parser/callback performance. Run with:

```bash
xcodebuild test -project NeoNV/NeoNV.xcodeproj -scheme NeoNV \
  -destination 'platform=macOS' -only-testing:NeoNVTests \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO
```

`testLongNoteTypingAndAutosaveAcrossSelectionChanges` edits a 50,000-line note
twice, switches to a short note between edits, and verifies the complete saved
contents. It stages its writable notes in the UI runner's temporary directory.

Manual smoke test on this branch: open a copy of a long note, type at the start,
middle, and end, switch among several files, return and type again. Pause for
autosave and reopen the note to confirm persistence. Also try `[[target` + Tab
and confirm completion preserves the text on following lines.
