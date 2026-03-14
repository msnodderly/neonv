#!/usr/bin/env bash
# autoresearch.sh — benchmark script for pi-autoresearch
#
# Runs the full-edit-workflow UI test and extracts the average wall-clock
# time in seconds. Prints a single decimal number — lower is better.
#
# Usage: ./autoresearch.sh
# Example output: 0.847

set -euo pipefail

cd "$(dirname "$0")/NeoNV"

# test-without-building skips the compiler entirely so that build time is never
# included in the benchmark metric. Run autoresearch.checks.sh first to ensure
# the test bundle is up to date.
RESULT=$(xcodebuild test-without-building \
  -scheme NeoNV \
  -destination 'platform=macOS' \
  -only-testing:NeoNVUITests/NeoNVUITests/testFullEditWorkflowPerformance \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO \
  2>&1) || {
  echo "ERROR: xcodebuild test-without-building failed." >&2
  echo "Run ./autoresearch.checks.sh first to build the test bundle." >&2
  echo "--- last 40 lines of xcodebuild output ---" >&2
  echo "$RESULT" | tail -40 >&2
  exit 1
}

# XCTest measure output format: "average: 0.234 s , σ: 0.012 s"
AVG=$(echo "$RESULT" | grep -oE 'average: [0-9]+\.[0-9]+' | tail -1 | awk '{print $2}')

if [ -z "$AVG" ]; then
  echo "ERROR: Could not extract timing metric from test output" >&2
  echo "--- last 40 lines of xcodebuild output ---" >&2
  echo "$RESULT" | tail -40 >&2
  exit 1
fi

echo "$AVG"
