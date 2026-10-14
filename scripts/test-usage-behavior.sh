#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-usage-behavior.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/CoucouKit/IslandScreenGeometry.swift \
    NotchBuddy/Sources/CoucouKit/IslandTypes.swift \
    NotchBuddy/Sources/App/TerminalBehavior.swift \
    NotchBuddy/Sources/App/UsageBehavior.swift \
    tests/UsageBehaviorTests.swift \
    -o "$TEST_DIR/usage-behavior-tests"
"$TEST_DIR/usage-behavior-tests"
