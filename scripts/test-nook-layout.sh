#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-nook-layout.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library \
    NotchBuddy/Sources/App/NookLayout.swift \
    tests/NookLayoutTests.swift \
    -o "$TEST_DIR/nook-layout-tests"
"$TEST_DIR/nook-layout-tests"
