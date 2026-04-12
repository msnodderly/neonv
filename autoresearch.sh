#!/usr/bin/env bash
# autoresearch.sh — benchmark script for pi-autoresearch
#
# Runs the full file-list scrolling UI test and extracts the average wall-clock
# time in seconds. Prints a single decimal number — lower is better.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_TMP="$HOME/Library/Containers/net.area51a.NeoNV/Data/tmp"
mkdir -p "$APP_TMP"
FIXTURES_DIR="$(mktemp -d "$APP_TMP/NeoNVAutoresearch.XXXXXX")"

cleanup() {
  rm -rf "$FIXTURES_DIR"
}
trap cleanup EXIT

"$ROOT_DIR/scripts/generate-test-fixtures.sh" "$FIXTURES_DIR" 500

cd "$ROOT_DIR/NeoNV"

# test-without-building skips the compiler entirely so that build time is never
# included in the benchmark metric. Run autoresearch.checks.sh first to ensure
# the test bundle is up to date.
RESULT=$(NEONV_TEST_NOTES_DIR="$FIXTURES_DIR" xcodebuild test-without-building \
  -scheme NeoNV \
  -destination 'platform=macOS' \
  -only-testing:NeoNVUITests/NeoNVUITests/testFullFileListScrollPerformance \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO \
  GENERATE_INFOPLIST_FILE=YES \
  2>&1) || {
  echo "ERROR: xcodebuild test-without-building failed." >&2
  echo "Run ./autoresearch.checks.sh first to build the test bundle." >&2
  echo "--- last 40 lines of xcodebuild output ---" >&2
  echo "$RESULT" | tail -40 >&2
  exit 1
}

AVG=$(echo "$RESULT" | grep -oE 'average: [0-9]+\.[0-9]+' | tail -1 | awk '{print $2}')

if [ -z "$AVG" ]; then
  echo "ERROR: Could not extract timing metric from test output" >&2
  echo "--- last 40 lines of xcodebuild output ---" >&2
  echo "$RESULT" | tail -40 >&2
  exit 1
fi

echo "$AVG"
