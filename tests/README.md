# MPM-Packages CraftOS Test Suite

## Overview

Testing is CraftOS-driven only. All automated runtime tests execute inside headless CraftOS-PC.

## Running Tests

### CraftOS integration scenarios

```bash
./tests/craftos/run_tests.sh
```

### Unified runner

```bash
./tests/run_all.sh
```

## Structure

```
tests/
├── run_all.sh
├── README.md
└── craftos/
    ├── run_tests.sh
    ├── startup.lua
    ├── runner.lua
    ├── lib/
    │   ├── harness.lua
    │   └── ui_driver.lua
    └── scenarios/
        ├── 01_*.lua
        ├── ...
        └── 19_mpm_storage_hygiene_scenario.lua
```

## Coverage Tracks

1. **Provisioning + startup lifecycle**
   - installs local `mpm` + `influx-collector`, configures `mpm startup influx-collector`, validates generated `/startup.lua`

2. **MPM storage hygiene**
    - verifies stale manifest file pruning on `mpm update`
    - verifies orphan dependency cleanup and `mpm prune --dry-run`
    - verifies stale core file pruning on `mpm selfupdate`
    - verifies disk usage output after update/selfupdate

## Coverage Critique

Current strengths:
- Real CraftOS runtime execution catches API-level behavioral regressions.
- End-to-end provisioning and startup lifecycle is covered for core `mpm` behavior.

Current weaknesses:
- Network interactions are mocked per-scenario and do not exercise real remote taps.
- No deterministic fault-injection matrix for low disk, write failures, and interrupted updates.
- No line/branch coverage metrics are collected, so blind spots are inferred, not measured.

## Extending Coverage

Add new numbered scenario files under `tests/craftos/scenarios/`.
Each scenario returns `function(harness)` and registers tests via `harness:test(name, fn)`.
