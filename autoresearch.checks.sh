#!/usr/bin/env bash
# autoresearch.checks.sh — correctness guard for pi-autoresearch
#
# Verifies that code changes:
#   1. Still compile successfully
#   2. Pass SwiftLint (no new errors)

set -euo pipefail

cd "$(dirname "$0")/NeoNV"

echo "==> Building NeoNV for testing (Debug)..."
BUILD_OUTPUT=$(xcodebuild build-for-testing \
  -scheme NeoNV \
  -configuration Debug \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO \
  GENERATE_INFOPLIST_FILE=YES \
  2>&1)
BUILD_STATUS=$?

if [ $BUILD_STATUS -ne 0 ]; then
  echo "$BUILD_OUTPUT" | grep -E "error:|warning:|note:" | head -40
  echo "---"
  echo "$BUILD_OUTPUT" | tail -5
  exit $BUILD_STATUS
else
  echo "$BUILD_OUTPUT" | tail -10
fi

echo "==> Running SwiftLint..."
if command -v swiftlint >/dev/null 2>&1; then
  swiftlint lint --quiet
else
  echo "warning: SwiftLint not installed — skipping lint check"
fi

echo "==> All checks passed."
