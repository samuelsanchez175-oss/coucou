#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-live-activities.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library \
    NotchBuddy/Sources/App/NookLayout.swift \
    NotchBuddy/Sources/App/LiveActivityBehavior.swift \
    tests/LiveActivityTests.swift \
    -o "$TEST_DIR/live-activity-tests"
"$TEST_DIR/live-activity-tests"
