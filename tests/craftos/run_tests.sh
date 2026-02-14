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

TOTAL_PASSED=0
TOTAL_FAILED=0
ALL_PASSED=true

# =============================================================================
# INTEGRATION TESTS (test_runner.lua)
# =============================================================================

echo "=== CraftOS-PC Integration Tests ==="
echo "Workspace: $MPM_PACKAGES"
echo ""

OUTPUT=$(timeout 30 "$CRAFTOS" --headless \
    --mount-ro /workspace="$MPM_PACKAGES" \
    --exec "dofile('/workspace/tests/craftos/test_runner.lua')" 2>&1)

# Extract clean output
RESULTS=$(echo "$OUTPUT" | grep -E "^\[PASS\]|\[FAIL\]|^Passed:|^ALL TESTS|^TESTS FAILED|^===|^Failures:" | uniq)
echo "$RESULTS"

PASSED=$(echo "$RESULTS" | grep -c "^\[PASS\]" || true)
FAILED=$(echo "$RESULTS" | grep -c "^\[FAIL\]" || true)
TOTAL_PASSED=$((TOTAL_PASSED + PASSED))
TOTAL_FAILED=$((TOTAL_FAILED + FAILED))

if ! echo "$OUTPUT" | grep -q "ALL TESTS PASSED"; then
    ALL_PASSED=false
fi

echo ""

# =============================================================================
# SWARM SIMULATION TESTS (swarm_simulation.lua)
# =============================================================================

echo "=== CraftOS-PC Swarm Simulation Tests ==="
echo ""

OUTPUT=$(timeout 120 "$CRAFTOS" --headless \
    --mount-ro /workspace="$MPM_PACKAGES" \
    --exec "dofile('/workspace/tests/craftos/swarm_simulation.lua')" 2>&1)

# Extract clean output
RESULTS=$(echo "$OUTPUT" | grep -E "^\[PASS\]|\[FAIL\]|^Passed:|^ALL TESTS|^TESTS FAILED|^===|^Failures:" | uniq)
echo "$RESULTS"

PASSED=$(echo "$RESULTS" | grep -c "^\[PASS\]" || true)
FAILED=$(echo "$RESULTS" | grep -c "^\[FAIL\]" || true)
TOTAL_PASSED=$((TOTAL_PASSED + PASSED))
TOTAL_FAILED=$((TOTAL_FAILED + FAILED))

if ! echo "$OUTPUT" | grep -q "ALL TESTS PASSED"; then
    ALL_PASSED=false
fi

echo ""

# =============================================================================
# SUMMARY
# =============================================================================

echo "=== CraftOS-PC Test Summary ==="
echo "Passed: $TOTAL_PASSED, Failed: $TOTAL_FAILED"

if [ "$ALL_PASSED" = true ]; then
    echo ""
    echo "SUCCESS: All CraftOS-PC tests passed"
    exit 0
else
    echo ""
    echo "FAILURE: Some CraftOS-PC tests failed"
    exit 1
fi
