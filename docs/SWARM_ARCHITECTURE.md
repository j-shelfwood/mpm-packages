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
5. **Display-only pairing codes** - Codes shown on screen only (never broadcast)

## Components

### Core Files

| File | Purpose |
|------|---------|
| `net/Pairing.lua` | Pairing logic with display-code security |
| `net/Crypto.lua` | HMAC signing, nonce tracking, ephemeral keys |
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

## Pairing Flow

### Step 1: Pocket Creates Swarm

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
    +-- Save to /shelfos_secret.txt
    +-- Save to /shelfos_pocket.config
    |
    v
POCKET (configured as controller)
```

### Step 2: Zone Joins via Pocket

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

## Message Types

### Pairing Protocol: `shelfos_pair`

| Message | Direction | Data | Notes |
|---------|-----------|------|-------|
| `PAIR_READY` | Zone -> Pocket | `{label, computerId}` | **No code** - code is display-only |
| `PAIR_DELIVER` | Pocket -> Zone | `{secret, zoneId}` | **Signed envelope** using display code as key |
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
| Pocket | `/shelfos_pocket.config` | `{isController}` |
| Zone | `/shelfos.config` | `{network: {secret, enabled}}` |

## Pairing Module API

### `Pairing.acceptFromPocket(callbacks)`

Zone waits for pocket to deliver secret. Displays a pairing code on screen
that the pocket user must enter.

```lua
local callbacks = {
    onDisplayCode = function(code) end,  -- Called with the code to display
    onStatus = function(msg) end,
    onSuccess = function(secret, zoneId) end,
    onCancel = function(reason) end
}
local success, secret, zoneId = Pairing.acceptFromPocket(callbacks)
```

**SECURITY:** The code passed to `onDisplayCode` must be displayed to the user
but NEVER transmitted over the network. The pocket user enters this code manually.

### `Pairing.deliverToPending(secret, zoneId, callbacks, timeout)`

Pocket listens for zones and delivers secret to selected one.
User must enter the code displayed on the zone's screen.

```lua
local callbacks = {
    onReady = function(computer) end,
    onCodePrompt = function(computer) end,  -- Return entered code
    onCodeInvalid = function(msg) end,
    onComplete = function(label) end,
    onCancel = function() end
}
local success, pairedComputer = Pairing.deliverToPending(secret, zoneId, callbacks, 30)
```

**SECURITY:** When user selects a computer, they are prompted to enter the code
shown on that computer's screen. The secret is then signed with that code
using `Crypto.wrapWith()` before transmission.

### Utility Functions

```lua
Pairing.generateSecret()  -- 32-char random secret
Pairing.generateCode()    -- XXXX-XXXX format display code
```

## Config Helper Functions

```lua
-- Check if zone is in swarm
Config.isInSwarm(config) -- returns true if secret exists

-- Set network secret (enables networking)
Config.setNetworkSecret(config, secret)
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
  |   Contains: {secret, zoneId}          |
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

1. No direct recovery - zones have secret but no way to share it
2. Create new swarm on new pocket
3. Re-pair all zones

### Zone Needs Re-pairing

1. Delete `/shelfos.config` on zone
2. Restart ShelfOS
3. Press L -> Accept from pocket
4. Pair from pocket

### Secret Compromised

1. On pocket: Leave Swarm -> Create new swarm
2. Re-pair all zones with new secret

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

### Request/Response Correlation

All request messages use `Protocol.createRequest()` which auto-generates a unique
`requestId` for response matching:

```lua
-- Protocol.lua
function Protocol.generateRequestId()
    return string.format("%d_%d_%d", os.getComputerID(), os.epoch("utc"), math.random(1000, 9999))
end

function Protocol.createRequest(msgType, data)
    return Protocol.createMessage(msgType, data, Protocol.generateRequestId())
end
```

## Known Limitations

1. **Single secret per swarm** - All zones share one secret
2. **No automatic re-keying** - Secret doesn't rotate
3. **Manual pairing required** - No auto-discovery of new zones
4. **RPC timeout** - Remote peripheral calls timeout after 5 seconds

## File Quick Reference

```
net/
|-- Pairing.lua           # Display-code pairing logic
|-- Crypto.lua            # HMAC, nonces, ephemeral keys
|-- Channel.lua           # Rednet + auto-crypto
|-- Protocol.lua          # Message types + requestId generation
|-- Discovery.lua         # Zone announcements
|-- PeripheralClient.lua  # Remote peripheral consumer
|-- PeripheralHost.lua    # Remote peripheral provider
|-- RemoteProxy.lua       # Proxy objects for remote peripherals
+-- RemotePeripheral.lua  # Global accessor for remote peripherals

shelfos/
|-- core/
|   |-- Config.lua        # isInSwarm(), setNetworkSecret()
|   +-- Kernel.lua        # acceptPocketPairing()
|-- pocket/
|   |-- App.lua           # Main pocket app + setup flow
|   +-- screens/
|       |-- SwarmStatus.lua   # Main swarm overview (default view)
|       +-- AddComputer.lua   # Pairing flow for new computers
+-- tools/
    |-- pair_accept.lua   # Bootstrap tool
    +-- link.lua          # Status display
```
