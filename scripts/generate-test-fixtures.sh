#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES_DIR="$ROOT_DIR/NeoNV/NeoNVUITests/Fixtures"
NOTE_COUNT="${1:-500}"

rm -rf "$FIXTURES_DIR"
mkdir -p "$FIXTURES_DIR"

for i in $(seq 1 "$NOTE_COUNT"); do
  num=$(printf "%04d" "$i")
  cat > "$FIXTURES_DIR/note-$num.md" <<EOF
# Note $num

Line 1 for Note $num.
Line 2 for Note $num.
Line 3 for Note $num.
EOF
done

echo "Generated $NOTE_COUNT fixtures in $FIXTURES_DIR"
