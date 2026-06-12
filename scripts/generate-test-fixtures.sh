#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [output-dir] [note-count]" >&2
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

DEFAULT_OUTPUT_DIR="$HOME/Library/Containers/net.area51a.NeoNV/Data/tmp/NeoNVUITests-Fixtures"
OUTPUT_DIR="${1:-$DEFAULT_OUTPUT_DIR}"
NOTE_COUNT="${2:-500}"

if [[ ! "$NOTE_COUNT" =~ ^[0-9]+$ ]]; then
  echo "error: note-count must be a positive integer" >&2
  usage
  exit 2
fi

if ((NOTE_COUNT < 1)); then
  echo "error: note-count must be a positive integer" >&2
  usage
  exit 2
fi

mkdir -p "$OUTPUT_DIR"
find "$OUTPUT_DIR" -maxdepth 1 -type f -name 'note-[0-9][0-9][0-9][0-9].md' -exec rm -f {} +
rm -f "$OUTPUT_DIR/snippet-probe.md" "$OUTPUT_DIR/deep-probe.md"

for ((i = 1; i <= NOTE_COUNT; i++)); do
  num="$(printf "%04d" "$i")"
  cat > "$OUTPUT_DIR/note-$num.md" <<EOF
# Note $num

Line 1 for Note $num.
Line 2 for Note $num.
Line 3 for Note $num.
EOF
done

# Probe note for testBodyMatchShowsRecenteredSnippet: its unique search term
# sits deep in the body, past the visible head of the list-row preview.
cat > "$OUTPUT_DIR/snippet-probe.md" <<EOF
# Snippet Probe

filler words to push the match deep filler words to push the match deep \
filler words to push the match deep the xylophone harvest begins at dawn
EOF

# Probe note for testSearchFindsMatchBeyondPreviewCap: its unique term sits
# past the 2 KB row-preview cap, so only the full-content index can find it.
{
  echo "# Deep Probe"
  echo
  for ((i = 0; i < 60; i++)); do
    echo "padding line $i to push the unique term well past the preview cap"
  done
  echo "the quetzalcoatl rises at dusk"
} > "$OUTPUT_DIR/deep-probe.md"

echo "Generated $NOTE_COUNT fixtures in $OUTPUT_DIR"
