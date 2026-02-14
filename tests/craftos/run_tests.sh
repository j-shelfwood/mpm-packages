#!/bin/bash
# Run ShelfOS tests inside CraftOS-PC headless emulator
# This provides a realistic CC:Tweaked environment for integration testing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MPM_PACKAGES="$(dirname "$(dirname "$SCRIPT_DIR")")"
CRAFTOS="/Applications/CraftOS-PC.app/Contents/MacOS/craftos"

# Check CraftOS-PC is installed
if [ ! -x "$CRAFTOS" ]; then
    echo "ERROR: CraftOS-PC not found at $CRAFTOS"
    echo "Install from: https://www.craftos-pc.cc/"
    exit 1
fi

# Run tests
echo "=== CraftOS-PC Integration Tests ==="
echo "Workspace: $MPM_PACKAGES"
echo ""

# Use timeout to prevent hanging
OUTPUT=$(timeout 30 "$CRAFTOS" --headless \
    --mount-ro /workspace="$MPM_PACKAGES" \
    --exec "dofile('/workspace/tests/craftos/test_runner.lua')" 2>&1)

# Extract the clean output (last lines after the terminal rendering)
# The headless mode outputs character-by-character, so we parse for key lines
echo "$OUTPUT" | grep -E "^\[PASS\]|\[FAIL\]|^Passed:|^ALL TESTS|^TESTS FAILED|^===|^Failures:" | uniq

# Check exit status
if echo "$OUTPUT" | grep -q "ALL TESTS PASSED"; then
    echo ""
    echo "SUCCESS: All CraftOS-PC integration tests passed"
    exit 0
else
    echo ""
    echo "FAILURE: Some CraftOS-PC integration tests failed"
    exit 1
fi
