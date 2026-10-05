#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-nook-playback.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library \
    NotchBuddy/Sources/App/NookLayout.swift \
    tests/NookPlaybackTests.swift \
    -o "$TEST_DIR/nook-playback-tests"
"$TEST_DIR/nook-playback-tests"
