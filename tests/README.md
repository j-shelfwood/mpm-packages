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
        ├── 01_readme_contract_scenario.lua
        ├── 02_shelfos_swarm_boot_scenario.lua
        ├── 03_pairing_contract_scenario.lua
        ├── 04_ui_keystroke_interaction_scenario.lua
        ├── 05_mpm_install_startup_scenario.lua
        ├── 06_pairing_runtime_scenario.lua
        └── 07_view_rendering_scenario.lua
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

## Extending Coverage

Add new numbered scenario files under `tests/craftos/scenarios/`.
Each scenario returns `function(harness)` and registers tests via `harness:test(name, fn)`.
