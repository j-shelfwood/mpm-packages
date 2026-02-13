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

## Terminal Menu

While running, ShelfOS displays a menu at the bottom of the terminal:

```
[M] Monitors  [S] Status  [L] Link  [R] Reset  [Q] Quit
```

| Key | Action |
|-----|--------|
| `M` | Monitor overview - view and change monitor views |
| `S` | Show current configuration (zone, monitors, network) |
| `L` | Network linking menu (create/join network) |
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
| Energy Storage | EnergyGraph |
| None | Clock |

When multiple monitors are connected, ShelfOS assigns variety (StorageGraph, ItemBrowser, EnergyGraph, etc.) rather than duplicates.

## Network Swarm

Link multiple computers to work as a unified system with **shared peripherals**.

### What Swarm Enables

When computers join the same swarm:

- **Peripheral Sharing** - ME Bridges, energy storage, and other peripherals are accessible from any computer in the swarm
- **Remote Views** - A computer without a local ME Bridge can display AE2 views using a remote bridge
- **Distributed Monitoring** - Place monitors anywhere in your base, connected to any swarm computer

### Pocket Computer as Controller

ShelfOS uses a **pocket-as-queen** architecture:

- Your **pocket computer** holds the swarm secret and acts as the controller
- **Zone computers** (with monitors) must be paired with your pocket to join
- This ensures only you can add computers to your swarm

### Setting Up Your Swarm

#### Step 1: Create Swarm on Pocket

1. Install ShelfOS on an **Advanced Pocket Computer** (with ender modem recommended)
2. Run `mpm run shelfos` - auto-detects pocket mode
3. Select **"2. Create Swarm"**
4. Note the pairing code displayed

#### Step 2: Pair Zone Computers

On each zone computer (with monitors):

1. Run `mpm run shelfos`
2. You'll see: "Not in swarm - Press L -> Accept from pocket"
3. Press `L` -> **"Accept from pocket"**
4. On your pocket: Select **"2. Add Computer"**
5. Select the zone computer from the list, press Enter
6. Zone receives secret and shows "Pairing successful!"
7. **Restart ShelfOS** on the zone to connect

#### Step 3: Verify Connection

After restart, the zone should show:
- "Network: wireless/ender modem"
- Swarm peer count
- Remote peripherals discovered

### Alternative: Zone-to-Zone Pairing

If you already have one zone in the swarm, it can share the secret:

1. On existing zone: Press `L` -> **"Host pairing session"**
2. On new zone: Press `L` -> **"Join existing swarm"** -> enter code
3. Restart new zone

### Modem Requirements

| Modem Type | Range | Cross-Dimension |
|------------|-------|-----------------|
| Wired | ~256 blocks | No |
| Wireless | ~64 blocks | No |
| Ender | Unlimited | Yes |

**Recommended:** Ender modem for pocket (unlimited range, works everywhere)

## Architecture

```
shelfos/
├── start.lua           # Entry point (auto-detects pocket/display/headless)
├── core/
│   ├── Kernel.lua      # Main orchestrator (parallel event loops)
│   ├── Config.lua      # Configuration management
│   ├── ConfigUI.lua    # View configuration UI
│   ├── Monitor.lua     # Per-monitor lifecycle + window buffering
│   ├── Terminal.lua    # Split terminal (logs + menu bar)
│   └── Zone.lua        # Zone identity
├── input/
│   └── Menu.lua        # Terminal menu handlers
├── modes/
│   └── headless.lua    # Headless peripheral host mode
├── pocket/
│   ├── start.lua       # Pocket computer entry
│   ├── App.lua         # Pocket UI + swarm management
│   └── Notifications.lua
└── tools/
    ├── setup.lua       # Configuration wizard
    ├── link.lua        # Network pairing CLI
    ├── pair_accept.lua # Bootstrap pairing (headless nodes)
    └── migrate.lua     # displays.config migration
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

### Energy & Machines

| View | Description |
|------|-------------|
| `EnergyGraph` | Energy storage graph |
| `EnergyStatus` | Energy capacity display |
| `MachineStatus` | Machine activity monitor |

### General

| View | Description |
|------|-------------|
| `Clock` | Time and weather display |

## Multiplayer Security

On multiplayer servers, ShelfOS uses HMAC-like message signing:

- All network messages are signed with a shared secret
- Timestamps prevent replay attacks
- Nonces prevent duplicate message injection
- Only computers with the secret can communicate

The secret is generated during `link new` and shared via the pairing process.

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
- Check that the pairing code matches exactly

### Views not rendering
- Press `Q` to quit and check for error messages
- Verify peripheral connections
- Press `R` to reset configuration, then restart

### Remote peripherals not working
- Ensure both computers have restarted after joining the swarm
- Check that the host computer is running ShelfOS
- Verify network connectivity (same modem type, in range)
