#!/bin/bash
# Run CraftOS integration scenarios in headless emulator

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MPM_PACKAGES="$(dirname "$(dirname "$SCRIPT_DIR")")"
REPO_ROOT="$(dirname "$MPM_PACKAGES")"
CRAFTOS="/Applications/CraftOS-PC.app/Contents/MacOS/craftos"

if [ ! -x "$CRAFTOS" ]; then
    echo "ERROR: CraftOS-PC not found at $CRAFTOS"
    echo "Install from: https://www.craftos-pc.cc/"
    exit 1
fi

echo "=== CraftOS Integration Tests ==="
echo "Workspace: $MPM_PACKAGES"
echo ""

OUTPUT=$(timeout 120 "$CRAFTOS" --headless \
    --mount-ro /workspace="$REPO_ROOT" \
    --exec "dofile('/workspace/mpm-packages/tests/craftos/runner.lua')" 2>&1)

CLEAN_OUTPUT=$(echo "$OUTPUT" | tr -d '\r')
RESULTS=$(echo "$CLEAN_OUTPUT" \
    | sed 's/[[:space:]]*$//' \
    | grep -E '^=== CraftOS Integration Scenarios ===$|^Executed [0-9]+ tests, [0-9]+ failed$|^ALL TESTS PASSED$|^TESTS FAILED$' \
    | tail -n 3)
echo "$RESULTS"

echo ""
if echo "$CLEAN_OUTPUT" | grep -q "ALL TESTS PASSED"; then
    echo "SUCCESS: CraftOS integration scenarios passed"
    exit 0
fi

echo "FAILURE: CraftOS integration scenarios failed"
exit 1
