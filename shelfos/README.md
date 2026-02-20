# ShelfOS

Base information system for CC:Tweaked.

## Scope

ShelfOS is the zone-computer runtime in a two-package model:
- `shelfos` runs on monitor/zone computers.
- `shelfos-swarm` runs on pocket computers as swarm authority.

ShelfOS supports both monitor-attached and terminal-only (0 monitor) nodes under the same kernel/runtime.

## Install and Run

- Install: `mpm install shelfos`
- Run: `mpm run shelfos`
- Pocket swarm authority run command: `mpm run shelfos-swarm`

## Runtime Contract

### Modes

- Monitor mode: renders monitor views and terminal dashboard/menu.
- Terminal-only mode: no monitor rendering; terminal dashboard/menu remains active.

### Terminal Keys

| Key | Action |
|-----|--------|
| `M` | Open monitor/view management |
| `S` | Open status view |
| `L` | Open swarm link menu |
| `R` | Factory reset and reboot |
| `Q` | Quit ShelfOS |

### Monitor Interaction Contract

- Touching monitor body reveals settings affordance.
- Settings affordance auto-hides after inactivity timeout.
- Selecting a view applies immediately to the touched monitor.
- `monitor_resize` triggers monitor reinitialization and relayout.
- Runtime peripheral attach/detach is self-healed: configured monitors reconnect and resume rendering when reattached.

Implementation is authoritative in:
- `mpm-packages/shelfos/core/Monitor.lua`
- `mpm-packages/shelfos/core/MonitorConfigMenu.lua`
- `mpm-packages/shelfos/input/Menu.lua`

## Boot and Assignment Rules

On startup ShelfOS:
1. Discovers monitors.
2. Detects available peripherals.
3. Resolves mountable views from installed packages.
4. Applies persisted monitor/view config when present.
5. Falls back to auto-assignment on first run.

Factory reset behavior:
- Deletes ShelfOS config.
- Writes reset marker.
- Next boot initializes discovered monitors to `Clock` before normal assignment resumes.

## Swarm Contract

- Zone nodes join swarms only after pocket-issued pairing.
- Pairing entrypoint on zone node is `L` menu action: `Accept from pocket`.
- Pairing delivers swarm secret and identity.
- Network operations require a modem.
- Remote peripherals are internally identity-scoped to avoid name collision across hosts.
- Local peripherals remain preferred when compatible.

## Setting Up Your Swarm

- On pocket: run `mpm run shelfos-swarm` and create/manage swarm authority.
- On zone nodes: run `mpm run shelfos`, then use `L` -> `Accept from pocket`.

## Security Model

- Swarm messages are signed with shared secret.
- Replay resistance uses timestamp/nonce validation.
- Unpaired nodes cannot participate in swarm RPC/discovery.

## Configuration

Path: `/shelfos.config`

Top-level fields:
- `version`: config schema version.
- `zone`: node identity metadata.
- `monitors`: array of monitor/view assignments.
- `network`: swarm credentials and network state.
- `settings`: runtime toggles/defaults.

Monitor entry contract:
- `peripheral`: monitor peripheral name.
- `label`: display label.
- `view`: mounted view name.
- `viewConfig`: per-view configuration table.

Schema validation and defaults are implemented in:
- `mpm-packages/shelfos/core/Config.lua`

## Dependencies

ShelfOS expects these packages/modules at runtime:
- `views`
- `ui`
- `net`
- `peripherals`
- `utils`

## Migration

Legacy `displays.config` migration command:
- `mpm run shelfos migrate`

## Architecture References

- `../docs/SWARM_ARCHITECTURE.md`
- `../docs/RENDERING_ARCHITECTURE.md`
- `../docs/PERIPHERAL_PROXY_ARCHITECTURE.md`

## Troubleshooting Contract

- No monitors detected: verify peripheral visibility and monitor attachment.
- No views mountable: verify `views` package installation and required peripherals.
- Swarm unavailable: verify modem availability and pairing state.
- Pocket warning on zone host: run `shelfos` on zone computers and `shelfos-swarm` on pocket computers.
