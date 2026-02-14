#!/bin/bash
# Unified test runner for mpm-packages
# Runs both Lua unit tests and CraftOS-PC integration tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MPM_PACKAGES="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_PASSED=0
TOTAL_FAILED=0

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           MPM-PACKAGES TEST SUITE                          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# LUA UNIT TESTS
# =============================================================================

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  Running Lua Unit Tests (Native Lua 5.4)${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

LUA_BIN="${LUA_BIN:-/opt/homebrew/bin/lua}"

if [ ! -x "$LUA_BIN" ]; then
    echo -e "${RED}ERROR: Lua not found at $LUA_BIN${NC}"
    echo "Set LUA_BIN environment variable to your Lua interpreter"
    exit 1
fi

LUA_OUTPUT=$("$LUA_BIN" "$MPM_PACKAGES/tests/lua/run.lua" "$MPM_PACKAGES" 2>&1)
LUA_EXIT=$?

# Parse results
LUA_PASSED=$(echo "$LUA_OUTPUT" | grep -c "^\[PASS\]" || true)
LUA_FAILED=$(echo "$LUA_OUTPUT" | grep -c "^\[FAIL\]" || true)

# Show output
echo "$LUA_OUTPUT" | while read -r line; do
    if [[ "$line" == "[PASS]"* ]]; then
        echo -e "${GREEN}$line${NC}"
    elif [[ "$line" == "[FAIL]"* ]]; then
        echo -e "${RED}$line${NC}"
    elif [[ "$line" == "Executed"* ]]; then
        echo -e "${BLUE}$line${NC}"
    else
        echo "$line"
    fi
done

echo ""

TOTAL_PASSED=$((TOTAL_PASSED + LUA_PASSED))
TOTAL_FAILED=$((TOTAL_FAILED + LUA_FAILED))

# =============================================================================
# CRAFTOS-PC INTEGRATION TESTS (Optional)
# =============================================================================

CRAFTOS="/Applications/CraftOS-PC.app/Contents/MacOS/craftos"

if [ -x "$CRAFTOS" ]; then
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  Running CraftOS-PC Integration Tests (CC:Tweaked Environment)${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    CRAFTOS_OUTPUT=$(timeout 60 "$CRAFTOS" --headless \
        --mount-ro /workspace="$MPM_PACKAGES" \
        --exec "dofile('/workspace/tests/craftos/test_runner.lua')" 2>&1 || true)

    # Extract clean results from noisy headless output
    # The headless mode outputs character-by-character, so we grep for complete lines
    CRAFTOS_RESULTS=$(echo "$CRAFTOS_OUTPUT" | grep -E "^\[PASS\]|\[FAIL\]|^Passed:|^ALL|^TESTS" | uniq | tail -30)

    CRAFTOS_PASSED=$(echo "$CRAFTOS_RESULTS" | grep -c "^\[PASS\]" || true)
    CRAFTOS_FAILED=$(echo "$CRAFTOS_RESULTS" | grep -c "^\[FAIL\]" || true)

    # Show results
    echo "$CRAFTOS_RESULTS" | while read -r line; do
        if [[ "$line" == "[PASS]"* ]]; then
            echo -e "${GREEN}$line${NC}"
        elif [[ "$line" == "[FAIL]"* ]]; then
            echo -e "${RED}$line${NC}"
        elif [[ "$line" == "Passed:"* ]]; then
            echo -e "${BLUE}$line${NC}"
        elif [[ "$line" == "ALL TESTS PASSED"* ]]; then
            echo -e "${GREEN}$line${NC}"
        elif [[ "$line" == "TESTS FAILED"* ]]; then
            echo -e "${RED}$line${NC}"
        else
            echo "$line"
        fi
    done

    echo ""

    TOTAL_PASSED=$((TOTAL_PASSED + CRAFTOS_PASSED))
    TOTAL_FAILED=$((TOTAL_FAILED + CRAFTOS_FAILED))
else
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  CraftOS-PC Integration Tests (SKIPPED)${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "CraftOS-PC not found. Install from: https://www.craftos-pc.cc/"
    echo ""
fi

# =============================================================================
# SUMMARY
# =============================================================================

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                        SUMMARY                             ║${NC}"
echo -e "${BLUE}╠════════════════════════════════════════════════════════════╣${NC}"

if [ $TOTAL_FAILED -eq 0 ]; then
    echo -e "${BLUE}║${NC}  ${GREEN}✓ PASSED: $TOTAL_PASSED${NC}"
    echo -e "${BLUE}║${NC}  ${GREEN}✗ FAILED: $TOTAL_FAILED${NC}"
    echo -e "${BLUE}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC}  ${GREEN}ALL TESTS PASSED${NC}"
else
    echo -e "${BLUE}║${NC}  ${GREEN}✓ PASSED: $TOTAL_PASSED${NC}"
    echo -e "${BLUE}║${NC}  ${RED}✗ FAILED: $TOTAL_FAILED${NC}"
    echo -e "${BLUE}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC}  ${RED}SOME TESTS FAILED${NC}"
fi

echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"

if [ $TOTAL_FAILED -gt 0 ]; then
    exit 1
fi
