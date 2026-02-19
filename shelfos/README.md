# ShelfOS

Base Information System for CC:Tweaked - Multi-monitor display management with touch controls and network swarm support.

## Quick Start

```
mpm install shelfos
mpm run shelfos
```

That's it. ShelfOS auto-discovers connected monitors and assigns appropriate views based on available peripherals.

## Features

- **Zero-touch setup** - Automatically detects monitors and peripherals
- **Touch controls** - Tap to reveal settings button, tap again to open view selector
- **Smart view assignment** - Assigns relevant views based on connected peripherals
- **Network swarm** - Link multiple computers to share peripherals across your base
- **Secure networking** - HMAC-signed messages for multiplayer servers
- **Live terminal dashboard** - Default mode now shows activity lights and runtime metrics instead of raw boot logs
- **Headless activity dashboard** - Live terminal indicators for discovery, RPC calls, rescans, and network throughput

## Terminal Menu

While running, ShelfOS displays a menu at the bottom of the terminal:

```
[M] Monitors  [S] Status  [L] Link  [R] Reset  [Q] Quit
```

| Key | Action |
|-----|--------|
| `M` | Monitor overview - view and change monitor views |
| `S` | Show current configuration (zone, monitors, network) |
| `L` | Network linking menu (pair with pocket) |
| `R` | Reset configuration (delete and restart fresh) |
| `Q` | Quit ShelfOS |

### Monitors Menu

Press `M` to open the monitors overview:

```
=== Monitors ===

[1] monitor_0
    View: StorageGraph
[2] monitor_1
    View: ItemBrowser

Commands:
  [1-2] Select monitor to cycle view
  [B] Back to main menu
```

Select a monitor number to change its view:

```
=== Select View ===

Monitor: monitor_0
Current: StorageGraph

[1] StorageGraph <--
[2] ItemBrowser
[3] FluidBrowser
[4] Clock

[N] Next view  [P] Previous view  [B] Back
```

## Touch Controls

On advanced monitors, ShelfOS uses a settings-button pattern:

1. **Touch anywhere** on the monitor to reveal the settings button `[*]`
2. **Tap the `[*]` button** (bottom-right corner) to open the view selector
3. The button auto-hides after 3 seconds if not tapped

### View Selector (On-Monitor)

When you tap `[*]`, a menu appears directly on the monitor:

```
+----------------------------------+
|         Select View              |  <- Blue title bar
+----------------------------------+
|  > StorageGraph                  |  <- Current view (highlighted)
|    ItemBrowser                   |
|    FluidBrowser                  |
|    Clock                         |
+----------------------------------+
|            Cancel                |  <- Red cancel bar
+----------------------------------+
```

- **Tap a view name** to switch to it
- **Tap Cancel** to close without changing

This allows view changes directly from the monitor without using the terminal.

## Auto-Discovery

On first boot, ShelfOS:

1. Scans for connected monitors
2. Detects available peripherals (ME Bridge, inventories, energy storage, etc.)
3. Assigns appropriate views to each monitor
4. Saves configuration automatically

### View Assignment Priority

| Peripheral | Default View |
|------------|--------------|
| ME Bridge / RS Bridge | StorageGraph |
| Energy Detector | EnergySystem |
| Energy Storage (non-AE2) | EnergyOverview |
| None | Clock |

When multiple monitors are connected, ShelfOS assigns variety (StorageGraph, ItemBrowser, EnergySystem, etc.) rather than duplicates.

## Network Swarm

Link multiple computers to work as a unified system with **shared peripherals**.

### What Swarm Enables

When computers join the same swarm:

- **Peripheral Sharing** - ME Bridges, energy storage, and other peripherals are accessible from any computer in the swarm
- **Remote Views** - A computer without a local ME Bridge can display AE2 views using a remote bridge
- **Distributed Monitoring** - Place monitors anywhere in your base, connected to any swarm computer
- **Local-First Access** - If a computer has a directly attached peripheral (for example `me_bridge` next to the computer or on a wired modem side), ShelfOS prefers that local peripheral before using a remote proxy

### Pocket Computer as Controller

ShelfOS uses a **pocket-as-queen** architecture:

- Your **pocket computer** runs `shelfos-swarm` and acts as the swarm controller
- **Zone computers** (with monitors) run `shelfos` and must be paired with your pocket to join
- This ensures only you can add computers to your swarm

### Setting Up Your Swarm

#### Step 1: Create Swarm on Pocket

1. Install on an **Advanced Pocket Computer** (with ender modem recommended):
   ```
   mpm install shelfos-swarm
   mpm run shelfos-swarm
   ```
2. Select **[C] Create new swarm**
3. Enter a name for your swarm

#### Step 2: Pair Zone Computers

On each zone computer (with monitors):

1. Run `mpm run shelfos`
2. You'll see: "Not in swarm - Press L -> Accept from pocket"
3. Press `L` -> **"Accept from pocket"**
4. A pairing code appears on the zone's screen (e.g., `ABCD-EFGH`)
5. On your pocket: Select **[A] Add Computer**
6. Select the computer from the list
7. **Enter the code** shown on the zone's screen
8. Zone receives swarm secret + computer ID and connects automatically

#### Step 3: Verify Connection

After pairing, the zone should show:
- "Network: wireless/ender modem"
- Swarm peer count
- Remote peripherals discovered

### Headless Dashboard (Peripheral Host Nodes)

When a computer runs in headless peripheral-host mode, ShelfOS now renders a live dashboard instead of raw host log spam.

- **Activity lights** flash for `DISCOVER`, `CALL`, `ANNOUNCE`, `RX`, `RESCAN`, and `ERROR`
- **Performance panel** tracks loop timing and average remote call latency
- **Network throughput** shows inbound message rate (`messages/s`)
- **Live inventory** lists currently shared peripherals and updates after attach/detach or manual rescan

The status line above the key hints always shows the most recent background action (for example: discovery request sender, RPC target/method, or rescan result).

### Default Mode Terminal Dashboard

In normal ShelfOS mode (`mpm run shelfos` on a monitor computer), the terminal log area is now a dashboard instead of boot spam:

- Activity lights for swarm discovery, RPC calls, announces, network RX, rescans, and errors
- Runtime metrics (message rate, loop timing, remote call latency)
- Live monitor/view summary (`monitor -> current view`)
- Shared-local and remote peripheral counts

Bottom-row menu controls remain the same: `[M] [S] [L] [R] [Q]`.

### Modem Requirements

| Modem Type | Range | Cross-Dimension |
|------------|-------|-----------------|
| Wired | ~256 blocks | No |
| Wireless | ~64 blocks | No |
| Ender | Unlimited | Yes |

**Recommended:** Ender modem for pocket (unlimited range, works everywhere)

## Architecture

```
shelfos/                  # Zone computer package
├── start.lua             # Entry point
├── core/
│   ├── Kernel.lua        # Main orchestrator (parallel event loops)
│   ├── Config.lua        # Configuration management
│   ├── ConfigUI.lua      # View configuration UI
│   ├── Monitor.lua       # Per-monitor lifecycle + window buffering
│   ├── Paths.lua         # File path constants
│   ├── Terminal.lua      # Split terminal (logs + menu bar)
│   └── Zone.lua          # Zone identity
├── input/
│   └── Menu.lua          # Terminal menu handlers
├── modes/
│   └── headless.lua      # Headless peripheral host mode
├── ui/
│   └── PairingScreen.lua # Pairing code display
└── tools/
    ├── setup.lua         # Configuration wizard
    ├── link.lua          # Network status CLI
    ├── pair_accept.lua   # Bootstrap pairing (headless nodes)
    └── migrate.lua       # displays.config migration
```

For pocket computers, use the separate `shelfos-swarm` package:

```
shelfos-swarm/            # Pocket computer package
├── start.lua             # Entry point
├── App.lua               # Swarm controller UI
└── core/
    ├── SwarmAuthority.lua # Zone registry, credential issuance
    └── Paths.lua          # Pocket file paths
```

### Technical Documentation

- **[Swarm Architecture](../docs/SWARM_ARCHITECTURE.md)** - Detailed networking docs
- **[Rendering Architecture](../docs/RENDERING_ARCHITECTURE.md)** - Window buffering, view lifecycle
- **[Peripheral Proxy](../docs/PERIPHERAL_PROXY_ARCHITECTURE.md)** - Remote peripheral system

## Configuration File

Stored at `/shelfos.config`:

```lua
{
    version = 1,
    zone = {
        id = "zone_0_12345",
        name = "Main Base"
    },
    monitors = {
        {
            peripheral = "monitor_0",
            label = "monitor_0",
            view = "StorageGraph",
            viewConfig = {}
        }
    },
    network = {
        enabled = false,
        secret = nil
    },
    settings = {
        defaultSleepTime = 1,
        touchFeedback = true,
        showViewIndicator = true
    }
}
```

## Dependencies

- `views` - Display modules (StorageGraph, ItemBrowser, etc.)
- `ui` - Touch zones, overlays, widgets
- `net` - Crypto, protocol, discovery, peripheral proxy
- `peripherals` - AEInterface, etc.
- `utils` - Common utilities

## Available Views

Views are provided by the `views` package:

### Storage & Items (ME/RS Bridge)

| View | Description |
|------|-------------|
| `StorageGraph` | Storage capacity bar graph |
| `StorageBreakdown` | Storage by type breakdown |
| `NetworkDashboard` | Combined storage/energy overview |
| `ItemBrowser` | Interactive item list with crafting |
| `ItemList` | Grid display of all items |
| `ItemGauge` | Single item monitor with crafting |
| `ItemChanges` | Recent item flow tracking |
| `CellHealth` | Storage cell health status |
| `DriveStatus` | Drive bay status |

### Fluids (ME/RS Bridge)

| View | Description |
|------|-------------|
| `FluidBrowser` | Interactive fluid list with crafting |
| `FluidList` | Grid display of all fluids |
| `FluidGauge` | Single fluid monitor with crafting |
| `FluidChanges` | Recent fluid flow tracking |

### Chemicals (ME Bridge + Applied Mekanistics)

| View | Description |
|------|-------------|
| `ChemicalBrowser` | Interactive chemical list |
| `ChemicalList` | Grid display of all chemicals |
| `ChemicalGauge` | Single chemical monitor |
| `ChemicalChanges` | Recent chemical flow tracking |

### Crafting (ME Bridge)

| View | Description |
|------|-------------|
| `CraftingQueue` | Active crafting jobs |
| `CraftingCPU` | Single CPU status |
| `CPUOverview` | All crafting CPUs |
| `CraftableBrowser` | Browse craftable items |
| `PatternBrowser` | Browse crafting patterns |

### Energy (AE2/ME Bridge)

| View | Description |
|------|-------------|
| `EnergyGraph` | AE2 energy storage graph |
| `EnergyStatus` | AE2 input/output/net display |
| `NetworkDashboard` | AE2 storage + energy overview |

### Energy (General Power)

| View | Description |
|------|-------------|
| `EnergyOverview` | Cross-mod storage bank overview |
| `EnergySystem` | Manual IN/OUT detector mapping (multi-select), FE/t flow state, FE bank |

### Machines

| View | Description |
|------|-------------|
| `MachineGrid` | Machine activity grid |
| `MachineList` | Machine activity list + details |

### Changes View Data Model

`ItemChanges`, `FluidChanges`, and `ChemicalChanges` are **snapshot delta** views:

- A baseline snapshot is captured at period start.
- Current totals are sampled repeatedly during the period.
- Displayed change is `current - baseline` for each resource key.
- At period end, baseline resets to the latest snapshot.

This means the view shows net change over the configured window, not per-tick throughput.

Config options for these views:

| Config | Meaning |
|--------|---------|
| `periodSeconds` | Baseline reset interval (window size) |
| `sampleSeconds` | How often to resample data inside the window |
| `showMode` | Show gains, losses, or both |
| `minChange` | Ignore small deltas below threshold |

### General

| View | Description |
|------|-------------|
| `Clock` | Time and weather display |

## Multiplayer Security

On multiplayer servers, ShelfOS uses HMAC-like message signing:

- All network messages are signed with a shared secret
- Timestamps prevent replay attacks
- Nonces prevent duplicate message injection
- Only computers with the swarm secret can communicate

The secret is generated by the pocket computer and delivered during pairing.

## Legacy Migration

To migrate from the old `displays` package:

```
mpm run shelfos migrate
```

This imports your `displays.config` into ShelfOS format.

## Troubleshooting

### "No monitors found"
- Ensure monitors are connected via wired modems or directly adjacent
- Check that modems are attached and activated (right-click to connect)

### "No views available"
- Install the views package: `mpm install views`
- Some views require specific peripherals (ME Bridge for AE2 views)

### Network not connecting
- Verify both computers have modems
- Ensure modems are the same type (both wireless, or both ender)
- Check that the pairing code was entered correctly

### Views not rendering
- Press `Q` to quit and check for error messages
- Verify peripheral connections
- Press `R` to reset configuration, then restart

### Remote peripherals not working
- Ensure the zone has completed pairing (shows "in swarm")
- Check that the host computer is running ShelfOS
- Verify network connectivity (same modem type, in range)

### "Use: mpm run shelfos-swarm"
- This appears on pocket computers - pocket must use `shelfos-swarm` package
- Zone computers (with monitors) use `shelfos` package
