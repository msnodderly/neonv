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

for ((i = 1; i <= NOTE_COUNT; i++)); do
  num="$(printf "%04d" "$i")"
  cat > "$OUTPUT_DIR/note-$num.md" <<EOF
# Note $num

Line 1 for Note $num.
Line 2 for Note $num.
Line 3 for Note $num.
EOF
done

echo "Generated $NOTE_COUNT fixtures in $OUTPUT_DIR"
