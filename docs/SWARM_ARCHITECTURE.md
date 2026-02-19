# ShelfOS Swarm Architecture

Technical documentation for the ShelfOS swarm networking system.

## Overview

ShelfOS uses a **pocket-as-queen** architecture where a pocket computer acts as the swarm controller. Zone computers (with monitors) start unpaired and must receive credentials from a pocket computer to join.

```
                    POCKET COMPUTER
                   (Swarm Controller)
                   shelfos-swarm package
                          |
            +-------------+-------------+
            |             |             |
         ZONE A        ZONE B        ZONE C
        (Worker)      (Worker)      (Worker)
        shelfos package
```

## Key Principles

1. **No auto-generated secrets** - Zones don't create their own secrets
2. **Pocket is source of truth** - SwarmAuthority manages zone registry
3. **Explicit pairing required** - No networking until paired
4. **Secure by default** - HMAC-signed messages, nonces, timestamps
5. **Display-only pairing codes** - Codes shown on screen only (never broadcast)

## Components

### Packages

| Package | Device | Purpose |
|---------|--------|---------|
| `shelfos-swarm` | Pocket | Swarm controller with SwarmAuthority |
| `shelfos` | Zone | Display management with swarm networking |
| `crypto` | Both | PKI crypto (KeyPair, Envelope, Registry) |
| `net` | Both | Networking (Channel, Pairing, Protocol) |

### Core Files

| File | Purpose |
|------|---------|
| `crypto/KeyPair.lua` | Key generation and fingerprints |
| `crypto/Envelope.lua` | Per-identity message wrapping |
| `crypto/Registry.lua` | Zone registry for SwarmAuthority |
| `net/Pairing.lua` | Pairing logic with display-code security |
| `net/Crypto.lua` | HMAC signing, nonce tracking, ephemeral keys |
| `net/Channel.lua` | Rednet abstraction with auto crypto wrapping |
| `net/Protocol.lua` | Message types and validation |

### ShelfOS Integration

| File | Purpose |
|------|---------|
| `shelfos/core/Config.lua` | `isInSwarm()`, `setNetworkSecret()` |
| `shelfos/core/Kernel.lua` | Network init, pairing menu handlers |
| `shelfos-swarm/App.lua` | Swarm creation, zone management |
| `shelfos-swarm/core/SwarmAuthority.lua` | Zone registry, credential issuance |
| `shelfos/tools/pair_accept.lua` | Standalone bootstrap pairing |

## Pairing Flow

### Step 1: Pocket Creates Swarm

```
POCKET (unconfigured)
    |
    v
mpm run shelfos-swarm
    |
    v
Menu: [C] Create new swarm
    |
    v
SwarmAuthority:createSwarm(name)
    |
    +-- Generate swarm identity (id, secret, fingerprint)
    +-- Initialize zone Registry
    +-- Save to /swarm_identity.dat, /swarm_registry.dat
    |
    v
POCKET (configured as controller)
```

### Step 2: Zone Joins via Pocket

```
ZONE                                    POCKET
  |                                       |
  | L -> Accept from pocket               | Menu: [A] Add Computer
  v                                       v
KernelPairing.acceptFromPocket()        AddComputer screen
  |                                       |
  +-- Generate display code               |
  +-- Show code on screen                 |
  |   (code NEVER broadcast)              |
  |                                       |
  +-- Pairing.acceptFromPocket()          |
  |       |                               |
  |       +-- broadcast PAIR_READY ------>|  (no code in message)
  |           {label, computerId}         |
  |                                       |
  |                                       | Shows "Enter code from screen"
  |                                       | User types code they see
  |                                       |
  |                                       | SwarmAuthority:reservePairingCredentials()
  |                                       |   +-- Reuse/prepare computer secret
  |                                       |   +-- Keep change pending
  |                                       |
  |<------ PAIR_DELIVER (signed) ---------+
  |        Signed with code as key        |
  |        Contains swarm secret + id     |
  |                                       |
  +-- Verify with display code            |
  +-- Extract secret, save to config      |
  +-- send PAIR_COMPLETE ---------------->|
  |                                       | SwarmAuthority:commitPairingCredentials()
  |                                       |
  v                                       v
ZONE (in swarm)                         Shows fingerprint
```

**Security:** The pairing code is displayed on the zone's physical screen and never
transmitted. An attacker would need physical access to complete pairing.

## Message Types

### Pairing Protocol: `shelfos_pair`

| Message | Direction | Data | Notes |
|---------|-----------|------|-------|
| `PAIR_READY` | Zone -> Pocket | `{label, computerId}` | **No code** - code is display-only |
| `PAIR_DELIVER` | Pocket -> Zone | `{secret, computerId}` | **Signed envelope** using display code as key |
| `PAIR_COMPLETE` | Zone -> Pocket | `{label, success}` | Confirmation |
| `PAIR_REJECT` | Any | `{reason}` | Cancellation |

**PAIR_DELIVER data:**
```lua
{
    secret = "...",            -- Shared swarm secret
    computerId = "computer_123_..."
}
```

### Swarm Protocol: `shelfos` (encrypted)

All messages wrapped with `Crypto.wrap()`:

| Message | Purpose |
|---------|---------|
| `ANNOUNCE` | Zone advertising presence |
| `DISCOVER` | Request zone metadata |
| `PERIPH_ANNOUNCE` | Peripheral availability |
| `PERIPH_CALL` | Remote peripheral method call |
| `PERIPH_RESULT` | Method call response |

## Secret Storage

| Device | Location | Format |
|--------|----------|--------|
| Pocket | `/swarm_identity.dat` | `{id, name, secret, fingerprint, ...}` |
| Pocket | `/swarm_registry.dat` | `{swarmId, entries: {zoneId: entry}}` |
| Zone | `/shelfos.config` | `{network: {secret, enabled}}` |

## Boot Sequence

### Zone Computer (with monitors)

```
mpm run shelfos
  |
  +-- pocket API exists? --> "Use: mpm run shelfos-swarm"
  |
  +-- monitors exist? --> display mode (Kernel)
  |         |
  |         +-- Config.load()
  |         +-- Config.isInSwarm()?
  |         |       |
  |         |       +-- NO: "Not in swarm, press L"
  |         |       +-- YES: initializeNetwork()
  |         |
  |         +-- initializeMonitors()
  |         +-- run() parallel event loops
  |
  +-- no monitors --> headless mode
            |
            +-- Config.isInSwarm()?
            |       |
            |       +-- NO: "Run pair_accept tool"
            |       +-- YES: start peripheral hosting
```

### Pocket Computer

```
mpm run shelfos-swarm
  |
  +-- Check for modem
  +-- SwarmAuthority:exists()?
  |       |
  |       +-- YES: SwarmAuthority:load()
  |       +-- NO: Menu: [C] Create new swarm
  |
  +-- initNetwork() (rednet.host)
  +-- run() event loop
          |
          +-- [A] Add Computer
          +-- [C] View Computers
          +-- [D] Delete Swarm
          +-- [P] Peripherals
          +-- [Q] Quit
```

## Security Model

### Pairing Security (Display-Only Codes)

The pairing flow uses a **display-only code** model for secure secret delivery:

```
ZONE                                    POCKET
  |                                       |
  | Generates 8-char code                 |
  | Displays code on screen               |
  | (NEVER broadcasts code)               |
  |                                       |
  | broadcast PAIR_READY --------------->|  (no secret info)
  |   {label, computerId}                 |
  |                                       |
  |                                       | User sees zone in list
  |                                       | User selects zone
  |                                       | Pocket prompts: "Enter code"
  |                                       | User types code from screen
  |                                       |
  |<------ PAIR_DELIVER (signed) ---------|
  |   Signed with code as ephemeral key   |
  |   Contains: secret + computerId       |
  |                                       |
  | Verifies signature with display code  |
  | If valid: extracts secret, saves      |
  |                                       |
  | send PAIR_COMPLETE ----------------->|
  |                                       |
```

**Why this is secure:**
- The pairing code is NEVER transmitted over the network
- An attacker would need physical access to see the code on the zone's screen
- PAIR_DELIVER is signed with the code as an ephemeral HMAC key
- Invalid/forged deliveries are rejected without the code
- The code is single-use and expires after 60 seconds

**Crypto functions used:**
- `Crypto.wrapWith(message, code)` - Sign with ephemeral key
- `Crypto.unwrapWith(envelope, code)` - Verify with ephemeral key

### HMAC Signing

All swarm messages are signed:

```lua
envelope = {
    v = 1,
    p = serializedPayload,
    t = timestamp,
    n = nonce,
    s = hmac(secret, payload + timestamp + nonce)
}
```

### Nonce Tracking

Nonces are tracked in `_G._shelfos_crypto.nonces` to prevent replay attacks. Old nonces are cleaned up periodically (2 minute expiry).

## Recovery Scenarios

### Pocket Lost

If the pocket computer is lost/destroyed:

1. No direct recovery - zones have swarm secret but no registry
2. Create new swarm on new pocket
3. Re-pair all zones

### Zone Needs Re-pairing

1. Delete `/shelfos.config` on zone (or use Reset menu)
2. Restart ShelfOS
3. Press L -> Accept from pocket
4. Pair from pocket

### Secret Compromised

1. On pocket: Delete Swarm
2. Create new swarm
3. Re-pair all zones with new credentials

## Remote Peripheral RPC

ShelfOS enables peripheral sharing across ender modems via custom RPC, since
CC:Tweaked's native `modem.callRemote()` only works on wired networks.

### RPC Message Flow

```
Zone A (client)                     Zone B (host)
    |                                   |
    |  PERIPH_DISCOVER ---------------->|
    |                                   |  Enumerate local peripherals
    |  <-------------- PERIPH_LIST -----|  {name, type, methods}
    |                                   |
    |  Store in remotePeripherals       |
    |                                   |
    |  PERIPH_CALL -------------------->|  {peripheral, method, args}
    |  (with requestId)                 |
    |                                   |  peripheral.call(name, method, ...)
    |  <-------------- PERIPH_RESULT ---|  {results} (with matching requestId)
```

## Known Limitations

1. **Single swarm secret** - All zones share one swarm secret
2. **No automatic re-keying** - Secret doesn't rotate
3. **Manual pairing required** - No auto-discovery of new zones
4. **RPC timeout** - Remote peripheral calls timeout after 5 seconds

## File Quick Reference

```
crypto/
|-- KeyPair.lua           # Key generation, fingerprints
|-- Envelope.lua          # Per-identity wrapping (for SwarmAuthority)
|-- Registry.lua          # Zone registry
|-- Sign.lua              # Signing functions
+-- Verify.lua            # Verification functions

net/
|-- Pairing.lua           # Display-code pairing logic
|-- Crypto.lua            # HMAC, nonces, ephemeral keys
|-- Channel.lua           # Rednet + auto-crypto
|-- Protocol.lua          # Message types + requestId generation
|-- Discovery.lua         # Zone announcements
|-- PeripheralClient.lua  # Remote peripheral consumer
|-- PeripheralHost.lua    # Remote peripheral provider
+-- RemotePeripheral.lua  # Global accessor for remote peripherals

shelfos-swarm/            # Pocket computer package
|-- start.lua             # Entry point
|-- App.lua               # Main swarm controller UI
+-- core/
    |-- SwarmAuthority.lua    # Zone registry, credential issuance
    +-- Paths.lua             # Pocket file paths

shelfos/                  # Zone computer package
|-- start.lua             # Entry point (redirects pocket)
|-- core/
|   |-- Config.lua        # isInSwarm(), setNetworkSecret()
|   |-- Kernel.lua        # acceptPocketPairing(), network init
|   +-- Paths.lua         # Zone file paths
+-- tools/
    |-- pair_accept.lua   # Bootstrap pairing tool
    +-- link.lua          # Network status display
```
