#!/usr/bin/env bash
# autoresearch.checks.sh — correctness guard for pi-autoresearch
#
# Verifies that code changes:
#   1. Still compile successfully
#   2. Pass SwiftLint (no new errors)
#
# Exit 0 = checks pass (change is safe to benchmark)
# Exit non-zero = checks failed (change should be rejected)

set -euo pipefail

cd "$(dirname "$0")/NeoNV"

echo "==> Building NeoNV (Debug)..."
xcodebuild build \
  -scheme NeoNV \
  -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  2>&1 | tail -10

echo "==> Running SwiftLint..."
if command -v swiftlint >/dev/null 2>&1; then
  swiftlint lint --quiet
else
  echo "warning: SwiftLint not installed — skipping lint check"
fi

echo "==> All checks passed."
