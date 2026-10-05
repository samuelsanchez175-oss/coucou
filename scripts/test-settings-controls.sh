#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-settings-controls.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library \
    NotchBuddy/Sources/App/NookLayout.swift \
    NotchBuddy/Sources/App/LiveActivityBehavior.swift \
    NotchBuddy/Sources/App/SettingsBoard.swift \
    tests/SettingsControlTests.swift \
    -o "$TEST_DIR/settings-control-tests"
"$TEST_DIR/settings-control-tests"
