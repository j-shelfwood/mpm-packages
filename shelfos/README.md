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
- **Touch controls** - Cycle views by touching left/right halves of monitors
- **Smart view assignment** - Assigns relevant views based on connected peripherals
- **Network swarm** - Link multiple computers into a unified system
- **Secure networking** - HMAC-signed messages for multiplayer servers

## Commands

| Command | Description |
|---------|-------------|
| `mpm run shelfos` | Start ShelfOS (auto-configures on first run) |
| `mpm run shelfos setup` | Manual configuration wizard |
| `mpm run shelfos status` | Show current configuration |
| `mpm run shelfos reset` | Delete configuration and start fresh |
| `mpm run shelfos link new` | Create a new network swarm |
| `mpm run shelfos link <CODE>` | Join an existing network |

## Touch Controls

On advanced monitors:

```
+-------------------+-------------------+
|                   |                   |
|   Touch left      |   Touch right     |
|   = Previous      |   = Next view     |
|     view          |                   |
|                   |                   |
+-------------------+-------------------+
|        Touch bottom = Config mode     |
+---------------------------------------+
```

## Auto-Discovery

On first boot, ShelfOS:

1. Scans for connected monitors
2. Detects available peripherals (ME Bridge, inventories, energy storage, etc.)
3. Assigns appropriate views to each monitor
4. Saves configuration automatically

### View Assignment Priority

| Peripheral | Default View |
|------------|--------------|
| ME Bridge / RS Bridge | StorageCapacityDisplay |
| Energy Storage | EnergyStatusDisplay |
| Inventory | ChestDisplay |
| Fluid Storage | FluidMonitor |
| None | WeatherClock |

When multiple monitors are connected, ShelfOS assigns variety (StorageCapacity, Inventory, Fluids, etc.) rather than duplicates.

## Network Swarm

Link multiple computers to work as a unified system.

### Creating a Network (Host Computer)

```
mpm run shelfos link new
```

This generates:
- A shared secret for secure communication
- A pairing code to share with other computers

### Joining a Network (Other Computers)

```
mpm run shelfos link ABCD-EFGH
```

Enter the pairing code from the host. The computer will:
1. Contact the host over rednet
2. Receive the shared secret
3. Join the network

### Network Requirements

- **Wired modem** - Up to 256 blocks range (good for same-base)
- **Wireless modem** - Limited range, same dimension only
- **Ender modem** - Cross-dimension, unlimited range (recommended for distributed bases)

## Architecture

```
shelfos/
├── start.lua           # Entry point
├── core/
│   ├── Kernel.lua      # Main orchestrator
│   ├── Config.lua      # Configuration management
│   ├── Monitor.lua     # Per-monitor lifecycle
│   └── Zone.lua        # Zone identity
├── view/
│   └── Manager.lua     # View loading (re-exports views/Manager)
├── input/
│   ├── Touch.lua       # Touch handling
│   ├── ConfigMode.lua  # Configuration overlay
│   └── Remote.lua      # Remote input handling
├── pocket/
│   ├── start.lua       # Pocket computer entry
│   ├── App.lua         # Pocket UI
│   └── Notifications.lua
└── tools/
    ├── setup.lua       # Configuration wizard
    ├── link.lua        # Network pairing
    └── migrate.lua     # Legacy displays migration
```

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
            view = "StorageCapacityDisplay",
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

- `views` - Display modules (StorageCapacityDisplay, etc.)
- `ui` - Touch zones, overlays, widgets
- `net` - Crypto, protocol, discovery
- `peripherals` - AEInterface, etc.
- `utils` - Common utilities

## Available Views

Views are provided by the `views` package:

| View | Requires | Description |
|------|----------|-------------|
| StorageCapacityDisplay | ME/RS Bridge | AE2/RS storage capacity graph |
| InventoryDisplay | ME/RS Bridge | Item list with search |
| FluidMonitor | ME/RS Bridge | Fluid storage levels |
| InventoryChangesDisplay | ME/RS Bridge | Recent item changes |
| LowStockAlert | ME/RS Bridge | Low stock warnings |
| ChestDisplay | Inventory | Vanilla chest contents |
| EnergyStatusDisplay | Energy Storage | Energy levels |
| MachineActivityDisplay | Any machine | Machine status |
| WeatherClock | None | Time and weather |
| CraftingQueueDisplay | ME Bridge | AE2 crafting status |

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
- Press 'q' to quit and check for error messages
- Verify peripheral connections
- Try `mpm run shelfos reset` and restart
