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

1. **README + entrypoint contracts**
   - verifies onboarding instructions in `shelfos/README.md` map to real package entrypoints

2. **Swarm boot + UI keystroke interactions**
   - verifies `shelfos-swarm` startup guards and deterministic menu navigation using key events

3. **Provisioning + startup lifecycle**
   - installs local `mpm` + `shelfos`, configures `mpm startup shelfos`, validates generated `/startup.lua`

4. **Pairing runtime simulation**
   - drives `net/Pairing` state-machine flows in CraftOS runtime with deterministic event injection

5. **View rendering smoke**
   - renders real view modules (`views/Clock`) to an in-memory terminal buffer and asserts rendered output

6. **MPM storage hygiene**
   - verifies stale manifest file pruning on `mpm update`
   - verifies orphan dependency cleanup and `mpm prune --dry-run`
   - verifies stale core file pruning on `mpm selfupdate`
   - verifies disk usage output after update/selfupdate

## Coverage Critique

Current strengths:
- Real CraftOS runtime execution catches API-level behavioral regressions.
- End-to-end provisioning and startup lifecycle is already covered.

Current weaknesses:
- Network interactions are mostly mocked per-scenario and do not exercise real remote taps.
- No deterministic fault-injection matrix for low disk, write failures, and interrupted updates.
- No line/branch coverage metrics are collected, so blind spots are inferred, not measured.
- `mpm` core behaviors were previously underrepresented; scenario `19_*` begins filling this gap.

## Extending Coverage

Add new numbered scenario files under `tests/craftos/scenarios/`.
Each scenario returns `function(harness)` and registers tests via `harness:test(name, fn)`.
