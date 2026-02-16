#!/bin/bash
# Unified test runner (CraftOS integration only)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MPM_PACKAGES="$(dirname "$SCRIPT_DIR")"

echo "Running CraftOS integration suite..."
"$MPM_PACKAGES/tests/craftos/run_tests.sh"
