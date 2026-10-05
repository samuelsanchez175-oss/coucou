#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-island-motion.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library \
    NotchBuddy/Sources/App/IslandMotion.swift \
    tests/IslandMotionTests.swift \
    -o "$TEST_DIR/island-motion-tests"
"$TEST_DIR/island-motion-tests"
