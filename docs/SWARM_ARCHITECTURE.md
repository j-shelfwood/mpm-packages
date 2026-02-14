# ShelfOS Swarm Architecture

Technical documentation for the ShelfOS swarm networking system.

## Overview

ShelfOS uses a **pocket-as-queen** architecture where a pocket computer acts as the swarm controller. Zone computers (with monitors) start unpaired and must receive the swarm secret from a pocket computer to join.

```
                    POCKET COMPUTER
                   (Swarm Controller)
                          |
            +-------------+-------------+
            |             |             |
         ZONE A        ZONE B        ZONE C
        (Worker)      (Worker)      (Worker)
```

## Key Principles

1. **No auto-generated secrets** - Zones don't create their own secrets
2. **Pocket is source of truth** - The master secret originates from pocket
3. **Explicit pairing required** - No networking until paired
4. **Secure by default** - HMAC-signed messages, nonces, timestamps
5. **Display-only pairing codes** - Codes are never broadcast (physical security)

## Components

### Core Files

| File | Purpose |
|------|---------|
| `net/Pairing.lua` | Consolidated pairing logic (callbacks-based API) |
| `net/Crypto.lua` | HMAC signing, nonce tracking, secret management |
| `net/Channel.lua` | Rednet abstraction with auto crypto wrapping |
| `net/Protocol.lua` | Message types and validation |
| `net/Discovery.lua` | Zone discovery and announcements |

### ShelfOS Integration

| File | Purpose |
|------|---------|
| `shelfos/core/Config.lua` | `isInSwarm()`, `setNetworkSecret()` |
| `shelfos/core/Kernel.lua` | Network init, pairing menu handlers |
| `shelfos/pocket/App.lua` | Pocket UI, swarm creation/management |
| `shelfos/tools/pair_accept.lua` | Standalone bootstrap pairing |

## Pairing Flows

### Flow 1: Pocket Creates Swarm

```
POCKET (unconfigured)
    |
    v
Menu: "2. Create Swarm"
    |
    v
App:createSwarm()
    |
    +-- Pairing.generateSecret() --> secret
    +-- Pairing.generateCode() --> pairing code
    +-- Save to /shelfos_secret.txt
    +-- Save to /shelfos_pocket.config
    |
    v
POCKET (configured as controller)
```

### Flow 2: Zone Joins via Pocket

```
ZONE                                    POCKET
  |                                       |
  | L -> Accept from pocket               | Menu: Add Computer
  v                                       v
Kernel:acceptPocketPairing()            App:addComputerToSwarm()
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
  |<------ PAIR_DELIVER (signed) ---------+
  |        Signed with code as key        |
  |                                       |
  +-- Verify with display code            |
  +-- Extract secret, save to config      |
  +-- send PAIR_COMPLETE ---------------->|
  |                                       |
  v                                       v
ZONE (in swarm)                         Shows "Joined!"
```

**Security:** The pairing code is displayed on the zone's physical screen and never
transmitted. An attacker would need physical access to complete pairing.

### Flow 3: Pocket Joins Existing Swarm

If pocket needs to join an already-running swarm (recovery scenario):

```
ZONE (in swarm)                         POCKET (unconfigured)
  |                                       |
  | L -> Host pairing                     | Menu: Join Swarm
  v                                       v
Kernel:hostPairing()                    App:joinSwarm()
  |                                       |
  | (displays pairing code)               | (user enters code)
  |                                       |
  |<------ pair_request (code) -----------+
  |                                       |
  +-- validate code                       |
  +-- send pair_response (secret) ------->|
  |                                       |
  |                                       +-- Save secret
  |                                       |
  v                                       v
Still hosting                           POCKET (in swarm)
```

## Message Types

### Pairing Protocol: `shelfos_pair`

| Message | Direction | Data | Notes |
|---------|-----------|------|-------|
| `pair_request` | Any -> Host | `{code}` | Code-based join (zone to zone) |
| `pair_response` | Host -> Any | `{success, secret, pairingCode, zoneId, zoneName}` | Response to pair_request |
| `PAIR_READY` | Zone -> Pocket | `{label, computerId}` | **No code/token** - code is display-only |
| `PAIR_DELIVER` | Pocket -> Zone | `{secret, pairingCode, zoneId}` | **Signed envelope** using display code as key |
| `PAIR_COMPLETE` | Zone -> Pocket | `{label, success}` | Confirmation |
| `PAIR_REJECT` | Any | `{reason}` | Cancellation |

**IMPORTANT:** `PAIR_DELIVER` is wrapped in a signed envelope (`Crypto.wrapWith(msg, code)`)
where the code is the one displayed on the zone's screen. This ensures only the person
with physical access to the zone can complete pairing.

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
| Pocket | `/shelfos_secret.txt` | Raw secret string |
| Pocket | `/shelfos_pocket.config` | `{pairingCode, zoneId, zoneName, isController}` |
| Zone | `/shelfos.config` | `{network: {secret, pairingCode, enabled}}` |

## Pairing Module API

### `Pairing.acceptFromPocket(callbacks)`

Zone waits for pocket to deliver secret. Displays a pairing code on screen
that the pocket user must enter.

```lua
local callbacks = {
    onDisplayCode = function(code) end,  -- Called with the code to display
    onStatus = function(msg) end,
    onSuccess = function(secret, pairingCode, zoneId) end,
    onCancel = function(reason) end
}
local success, secret, pairingCode, zoneId = Pairing.acceptFromPocket(callbacks)
```

**SECURITY:** The code passed to `onDisplayCode` must be displayed to the user
but NEVER transmitted over the network. The pocket user enters this code manually.

### `Pairing.hostSession(secret, pairingCode, zoneId, zoneName, callbacks)`

Host pairing session for others to join with code.

```lua
local callbacks = {
    onJoin = function(computerId) end,
    onCancel = function() end
}
local clientsJoined = Pairing.hostSession(secret, code, zoneId, zoneName, callbacks)
```

### `Pairing.joinWithCode(code, callbacks)`

Join swarm using pairing code.

```lua
local callbacks = {
    onStatus = function(msg) end,
    onSuccess = function(response) end,
    onFail = function(error) end
}
local success, secret, pairingCode, zoneId, zoneName = Pairing.joinWithCode(code, callbacks)
```

### `Pairing.deliverToPending(secret, pairingCode, zoneId, zoneName, callbacks, timeout)`

Pocket listens for zones and delivers secret to selected one.
User must enter the code displayed on the zone's screen.

```lua
local callbacks = {
    onReady = function(computer) end,
    onCodePrompt = function(computer) end,  -- Return entered code (optional, fallback to terminal prompt)
    onCodeInvalid = function(msg) end,
    onComplete = function(label) end,
    onCancel = function() end
}
local success, pairedComputer = Pairing.deliverToPending(secret, code, zoneId, zoneName, callbacks, 30)
```

**SECURITY:** When user selects a computer, they are prompted to enter the code
shown on that computer's screen. The secret is then signed with that code
using `Crypto.wrapWith()` before transmission.

### Utility Functions

```lua
Pairing.generateSecret()  -- 32-char random secret
Pairing.generateCode()    -- XXXX-XXXX format pairing code
Pairing.generateToken()   -- 16-char one-time token
```

## Config Helper Functions

```lua
-- Check if zone is in swarm
Config.isInSwarm(config) -- returns true if secret exists

-- Set network secret (enables networking)
Config.setNetworkSecret(config, secret)

-- Ensure pairing code exists (only if already in swarm)
Config.ensurePairingCode(config)
```

## Boot Sequence

### Zone Computer (with monitors)

```
start.lua
  |
  +-- pocket API exists? --> pocket mode
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
start.lua
  |
  +-- pocket API exists? --> pocket mode (App)
            |
            +-- initModem() -- open rednet
            +-- loadSecret()
            |       |
            |       +-- exists: initNetwork() + full menu
            |       +-- missing: limited menu (Join/Create)
            |
            +-- run() event loop
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
  |   Contains: {secret, pairingCode}     |
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
- Even if intercepted, the secret cannot be extracted without the code
- The code is single-use and expires after 60 seconds

**Crypto functions used:**
- `Crypto.wrapWith(message, code)` - Sign with ephemeral key
- `Crypto.unwrapWith(envelope, code)` - Verify with ephemeral key

### HMAC Signing

All swarm messages are signed:

```lua
envelope = {
    data = originalMessage,
    nonce = randomString,
    timestamp = os.epoch("utc"),
    signature = hmac(secret, data + nonce + timestamp)
}
```

### Verification

```lua
function Crypto.verify(envelope)
    -- Check timestamp (reject if > 5 minutes old)
    -- Check nonce (reject if seen before)
    -- Verify signature matches
    return valid, data, error
end
```

### Nonce Tracking

Nonces are tracked in `_G._shelfos_crypto.nonces` to prevent replay attacks. Old nonces are cleaned up periodically.

## Recovery Scenarios

### Pocket Lost

If the pocket computer is lost/destroyed:

1. Any zone already in swarm can host pairing
2. New pocket can "Join Swarm" using zone's pairing code
3. New pocket receives secret, becomes controller

### Zone Needs Re-pairing

1. Delete `/shelfos.config` on zone
2. Restart ShelfOS
3. Press L -> Accept from pocket
4. Pair from pocket

### Secret Compromised

1. On pocket: Leave Swarm -> Create new swarm
2. Re-pair all zones with new secret

## Testing Checklist

- [ ] Pocket creates swarm (generates secret)
- [ ] Zone shows "Not in swarm" on first boot
- [ ] Zone accepts pairing from pocket
- [ ] Zone restarts and joins network
- [ ] Remote peripherals discovered
- [ ] Zone can host pairing (when in swarm)
- [ ] Pocket can join existing swarm
- [ ] Crypto errors don't spam when unpaired

## Known Limitations

1. **Single secret per swarm** - All zones share one secret
2. **No automatic re-keying** - Secret doesn't rotate
3. **Manual pairing required** - No auto-discovery of new zones
4. **Pocket UI basic** - Print-based, not graphical

## File Quick Reference

```
net/
├── Pairing.lua      # All pairing logic
├── Crypto.lua       # HMAC, nonces, secrets
├── Channel.lua      # Rednet + auto-crypto
├── Protocol.lua     # Message types
└── Discovery.lua    # Zone announcements

shelfos/
├── core/
│   ├── Config.lua   # isInSwarm(), setNetworkSecret()
│   └── Kernel.lua   # acceptPocketPairing(), hostPairing()
├── pocket/
│   └── App.lua      # createSwarm(), addComputerToSwarm(), joinSwarm()
└── tools/
    ├── pair_accept.lua  # Bootstrap tool
    └── link.lua         # CLI pairing
```
