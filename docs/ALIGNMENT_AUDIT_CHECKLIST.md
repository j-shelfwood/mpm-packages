# ShelfOS Alignment Audit Checklist

Use this checklist to find implementation drift and incomplete consolidations.

## 1) Identity & Discovery Parity

```bash
rg -n "rednet\.host|rednet\.unhost|KernelNetwork\.hostService|KernelNetwork\.close" mpm-packages/shelfos mpm-packages/net
```

Verify:
- service host/unhost lifecycle flows through shared helpers (not ad hoc calls)
- display and headless modes both register identity consistently

## 2) Remote Peripheral Identity Model

```bash
rg -n "remotePeripherals\[|remoteByName|remoteNameAlias|resolveInfo|<hostId>::<name>|::" mpm-packages/net mpm-packages/views mpm-packages/shelfos
```

Verify:
- no code paths assume `remotePeripherals[name]` uniqueness
- host-qualified keying is used where collisions are possible
- user-facing labels remain readable (`displayName`) while persisted IDs stay stable

## 3) Local-First Fallback Correctness

```bash
rg -n "hasType\(|getType\(|wrap\(|call\(" mpm-packages/net/RemotePeripheral.lua mpm-packages/net/PeripheralClient.lua
```

Verify:
- local-first behavior does not mask valid remote peripherals on type mismatch
- remote fallback remains available for ambiguous/local-false scenarios

## 4) Dashboard Metrics Semantics

```bash
rg -n "waitMsSamples|handlerMsSamples|recordEventWaitMs|recordHandlerMs|Wait avg/peak|Handler avg/peak" mpm-packages/shelfos/core mpm-packages/shelfos/modes
```

Verify:
- wait latency and handler execution are tracked separately
- no stale `loopMsSamples`/`Loop avg/peak` wording remains in runtime code

## 5) Redraw Churn Controls

```bash
rg -n "setRemoteCount|setSharedCount|needsRedraw|shouldRender" mpm-packages/shelfos/core
```

Verify:
- high-frequency counters only trigger redraw when value changes
- render cadence remains bounded and intentional

## 6) Docs vs Runtime Consistency

```bash
rg -n "loop timing|Loop avg/peak|remotePeripherals|Q/R/X|M/S/L/R/Q|headless" mpm-packages/shelfos/README.md mpm-packages/docs
```

Verify:
- docs describe current keymaps/metrics/identity behavior
- architecture docs reflect key-based remote identity and host metadata paths

## 7) Regression Safety

```bash
cd mpm-packages && ./tests/run_all.sh
```

Verify:
- no integration regression in existing CraftOS scenarios
- follow-up: add focused tests for collision/fallback/ordering invariants

## 8) Monitor Event Naming & Lifecycle

```bash
rg -n "monitor_touch|monitor_resize|peripheral_detach|discoverMonitors|os\\.pullEvent\\(\"monitor_touch\"\\)" mpm-packages/shelfos mpm-packages/ui mpm-packages/docs
```

Verify:
- no code/docs assume monitor events only return side names; CC:Tweaked may provide side or network ID
- monitor discovery in setup/pairing/runtime paths flows through `Config.discoverMonitors()` where canonicalization matters
- interactive monitor loops avoid accidental lifecycle blindness (filtered `os.pullEvent("monitor_touch")` sites should be reviewed for detach/resize handling)
- attach/detach reconnect expectations are documented and covered by scenarios
