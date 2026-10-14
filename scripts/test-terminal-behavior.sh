#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-terminal-behavior.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/CoucouKit/IslandScreenGeometry.swift \
    NotchBuddy/Sources/CoucouKit/IslandTypes.swift \
    NotchBuddy/Sources/App/NookLayout.swift \
    NotchBuddy/Sources/App/TerminalBehavior.swift \
    tests/TerminalBehaviorTests.swift -o "$TEST_DIR/terminal-behavior-tests"
"$TEST_DIR/terminal-behavior-tests"
