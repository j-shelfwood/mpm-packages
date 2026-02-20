# Peripheral Proxy Architecture

## Goal

Make ender modem peripheral access **identical** to wired modem peripheral sharing from the user/developer perspective.

```lua
-- This should work the same whether ME Bridge is:
-- 1. Local (attached directly)
-- 2. Remote via wired modem (CC:Tweaked native)
-- 3. Remote via ender modem (our proxy)

local ae = AEInterface.new()
local items = ae:items()
```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         PERIPHERAL NODE                              │
│                    (Computer with peripherals)                       │
├─────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────────┐    ┌──────────────────┐    │
│  │ ME Bridge   │───>│ PeripheralHost  │───>│  Ender Modem     │    │
│  │ Sensors     │    │                 │    │                  │    │
│  │ Energy      │    │ - Scans locals  │    │  Broadcasts:     │    │
│  └─────────────┘    │ - Handles RPC   │    │  - Availability  │    │
│                     │ - Caches data   │    │  - Periodic data │    │
│                     └─────────────────┘    └──────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                │ rednet (shelfos_peripheral)
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          DISPLAY NODE                                │
│                     (Computer with monitors)                         │
├─────────────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐    ┌─────────────────┐    ┌───────────────┐  │
│  │   Ender Modem    │───>│ PeripheralClient│───>│ RemoteProxy   │  │
│  │                  │    │                 │    │               │  │
│  │  Receives:       │    │ - Discovery     │    │ - Looks like  │  │
│  │  - Announcements │    │ - Subscriptions │    │   real periph │  │
│  │  - RPC responses │    │ - RPC calls     │    │ - Same API    │  │
│  └──────────────────┘    └─────────────────┘    └───────────────┘  │
│                                                         │           │
│                                                         ▼           │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                     Views / AEInterface                       │  │
│  │                                                               │  │
│  │  -- Unchanged code:                                           │  │
│  │  local p = peripheral.find("me_bridge")  -- Returns proxy!   │  │
│  │  local items = p.getItems()              -- Transparent RPC  │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Protocol Extensions (`net/Protocol.lua`)

```lua
Protocol.MessageType = {
    -- ... existing ...

    -- Peripheral Discovery
    PERIPH_ANNOUNCE = "periph_announce",    -- Host broadcasts available peripherals
    PERIPH_DISCOVER = "periph_discover",    -- Client requests peripheral list
    PERIPH_LIST = "periph_list",            -- Response with peripheral list

    -- Peripheral Subscriptions
    PERIPH_SUBSCRIBE = "periph_subscribe",  -- Client subscribes to updates
    PERIPH_UNSUBSCRIBE = "periph_unsubscribe",
    PERIPH_UPDATE = "periph_update",        -- Host pushes data update

    -- Peripheral RPC (Remote Procedure Call)
    PERIPH_CALL = "periph_call",            -- Client calls method on peripheral
    PERIPH_RESULT = "periph_result",        -- Host returns result
    PERIPH_ERROR = "periph_error",          -- Host returns error
}
```

### 2. PeripheralHost (`net/PeripheralHost.lua`)

Runs on computers that have peripherals to share.

```lua
PeripheralHost = {
    -- Configuration
    announceInterval = 10000,  -- 10 seconds

    -- State
    peripherals = {},          -- {name -> {type, methods, lastData}}
    subscribers = {},          -- {peripheralName -> {computerId -> {methods}}}

    -- Core functions
    scan(),                    -- Discover local peripherals
    announce(),                -- Broadcast availability
    handleCall(sender, msg),   -- Execute RPC and return result
    handleSubscribe(sender, msg),
    pushUpdates(),             -- Send cached data to subscribers
}
```

**Peripheral Announcement Message:**
```lua
{
    type = "periph_announce",
    data = {
        zoneId = "zone_123",
        zoneName = "Storage Room",
        peripherals = {
            {
                name = "me_bridge_0",
                type = "me_bridge",
                methods = {"getItems", "getFluid", "craftItem", ...}
            },
            {
                name = "energy_storage_1",
                type = "energyStorage",
                methods = {"getEnergy", "getEnergyCapacity", ...}
            }
        }
    }
}
```

### 3. PeripheralClient (`net/PeripheralClient.lua`)

Runs on computers that want to use remote peripherals.

```lua
PeripheralClient = {
    -- State
    remotePeripherals = {},    -- {key -> {key, name, hostId, type, methods, proxy}}
    remoteByName = {},         -- {name -> {key1, key2, ...}}
    subscriptions = {},        -- Active subscriptions
    cache = {},                -- Cached data with TTL

    -- Core functions
    discover(timeout),         -- Find remote peripherals
    find(type),                -- Find peripheral by type (local or remote)
    wrap(name),                -- Get proxy for peripheral
    subscribe(name, methods),  -- Subscribe to updates
    call(name, method, ...),   -- RPC call
}
```

### 4. RemoteProxy (`net/RemoteProxy.lua`)

Creates a proxy object that mimics a real peripheral.

```lua
function RemoteProxy.create(client, hostId, peripheralName, peripheralType, methods, key, displayName)
    local proxy = {}

    -- Generate method stubs for each available method
    for _, methodName in ipairs(methods) do
        proxy[methodName] = function(...)
            return client:call(peripheralName, methodName, ...)
        end
    end

    -- Add peripheral-like metadata
    proxy._isRemote = true
    proxy._hostId = hostId
    proxy._name = key or (tostring(hostId) .. "::" .. peripheralName)
    proxy._remoteName = peripheralName
    proxy._displayName = displayName or proxy._name
    proxy._type = peripheralType

    return proxy
end
```

### 5. Enhanced peripheral API (`net/RemotePeripheral.lua`)

Drop-in replacement for `peripheral` that checks remote peripherals.

```lua
RemotePeripheral = {
    client = nil,  -- PeripheralClient instance

    -- Mirrors peripheral.find() but includes remote
    find = function(type)
        -- Try local first
        local local_p = peripheral.find(type)
        if local_p then return local_p end

        -- Try remote
        if RemotePeripheral.client then
            return RemotePeripheral.client:find(type)
        end

        return nil
    end,

    -- Mirrors peripheral.wrap() but includes remote
    wrap = function(name)
        -- Try local first
        local local_p = peripheral.wrap(name)
        if local_p then return local_p end

        -- Try remote
        if RemotePeripheral.client then
            return RemotePeripheral.client:wrap(name)
        end

        return nil
    end,

    -- Get all peripherals (local + remote)
    getNames = function()
        local names = peripheral.getNames()
        if RemotePeripheral.client then
            for name, _ in pairs(RemotePeripheral.client.remotePeripherals) do
                table.insert(names, name)
            end
        end
        return names
    end
}
```

## Data Flow

### Discovery Flow

```
Display Node                           Peripheral Node
     │                                       │
     │──── PERIPH_DISCOVER ─────────────────>│
     │                                       │
     │<───── PERIPH_LIST ────────────────────│
     │     {peripherals: [...]}              │
     │                                       │
     │  (Creates RemoteProxy for each)       │
     │                                       │
```

### RPC Flow (Method Call)

```
View                Client              Network           Host              Peripheral
 │                    │                    │                │                    │
 │ p.getItems()       │                    │                │                    │
 │───────────────────>│                    │                │                    │
 │                    │ PERIPH_CALL        │                │                    │
 │                    │ {method, args}     │                │                    │
 │                    │───────────────────>│───────────────>│                    │
 │                    │                    │                │ p.getItems()       │
 │                    │                    │                │───────────────────>│
 │                    │                    │                │<───────────────────│
 │                    │                    │                │ {items...}         │
 │                    │                    │ PERIPH_RESULT  │                    │
 │                    │<───────────────────│<───────────────│                    │
 │<───────────────────│ {items...}         │                │                    │
 │                    │                    │                │                    │
```

### Subscription Flow (Push Updates)

```
Display Node                           Peripheral Node
     │                                       │
     │──── PERIPH_SUBSCRIBE ────────────────>│
     │     {name, methods, interval}         │
     │                                       │
     │<───── PERIPH_UPDATE ──────────────────│  (every interval)
     │     {name, data: {items: [...]}}      │
     │                                       │
     │<───── PERIPH_UPDATE ──────────────────│
     │                                       │
```

## Caching Strategy

### Client-Side Cache

```lua
cache = {
    ["me_bridge_0"] = {
        getItems = {
            data = {...},
            timestamp = 1234567890,
            ttl = 1000  -- 1 second
        },
        itemStorage = {
            data = {...},
            timestamp = 1234567890,
            ttl = 500   -- 0.5 seconds (changes frequently)
        }
    }
}
```

### Cache Policy by Method Type

| Method Type | TTL | Strategy |
|-------------|-----|----------|
| Static (getMethods) | 300s | Cache until disconnect |
| Inventory (getItems) | 1s | Short TTL, high frequency |
| Status (itemStorage) | 0.5s | Very short TTL |
| Actions (craftItem) | 0 | Never cache, always RPC |

## Integration with Existing Code

### Minimal Changes to AEInterface

```lua
-- Before:
function AEInterface.find()
    return peripheral.find("me_bridge")
end

-- After:
local RemotePeripheral = mpm('net/RemotePeripheral')

function AEInterface.find()
    -- RemotePeripheral.find checks local first, then remote
    return RemotePeripheral.find("me_bridge")
end
```

### Kernel Integration

```lua
-- In Kernel:boot()
if self.config.network.enabled then
    -- Initialize peripheral client for remote access
    local PeripheralClient = mpm('net/PeripheralClient')
    self.peripheralClient = PeripheralClient.new(self.channel)
    self.peripheralClient:discover(3)  -- 3 second discovery

    -- Make it available globally
    local RemotePeripheral = mpm('net/RemotePeripheral')
    RemotePeripheral.setClient(self.peripheralClient)
end
```

### Headless Mode (Peripheral-Only Node)

```lua
-- shelfos/modes/headless.lua
-- For computers with peripherals but no monitors

local PeripheralHost = mpm('net/PeripheralHost')
local Channel = mpm('net/Channel')

local function run()
    print("[ShelfOS] Starting in headless mode (peripheral host)")

    local channel = Channel.new()
    channel:open(true)  -- Prefer ender modem

    local host = PeripheralHost.new(channel)
    host:scan()
    host:announce()

    print("[ShelfOS] Hosting " .. #host.peripherals .. " peripheral(s)")

    -- Event loop: handle RPC requests
    while true do
        channel:poll(0.5)

        if host:shouldAnnounce() then
            host:announce()
        end

        host:pushUpdates()
    end
end

return { run = run }
```

## Error Handling

### Connection Loss

```lua
-- RemoteProxy method wrapper with retry
proxy[methodName] = function(...)
    local result, err = client:call(peripheralName, methodName, ...)

    if err == "timeout" then
        -- Try to rediscover
        client:rediscover(peripheralName)
        result, err = client:call(peripheralName, methodName, ...)
    end

    if err then
        -- Return nil like real peripheral would on disconnect
        return nil
    end

    return result
end
```

### Graceful Degradation

```lua
-- View can check if peripheral is available
if not ae or ae._isRemote and not ae:isConnected() then
    MonitorHelpers.writeCentered(monitor, 5, "Peripheral Offline", colors.red)
    MonitorHelpers.writeCentered(monitor, 6, "Reconnecting...", colors.gray)
    return
end
```

## File Structure

```
net/
├── Channel.lua          # Existing - rednet abstraction
├── Protocol.lua         # Extended - new message types
├── Discovery.lua        # Existing - zone discovery
├── Crypto.lua           # Existing - message signing
├── PeripheralHost.lua   # NEW - serves peripherals
├── PeripheralClient.lua # NEW - consumes remote peripherals
├── RemoteProxy.lua      # NEW - proxy object generator
└── RemotePeripheral.lua # NEW - drop-in peripheral replacement

shelfos/
├── modes/
│   ├── display.lua      # NEW - monitor mode (current default)
│   └── headless.lua     # NEW - peripheral host mode
└── start.lua            # Modified - detect mode
```

## Implementation Order

### Phase 1: Core Protocol
1. Add `PERIPH_*` message types to Protocol.lua
2. Create PeripheralHost.lua (basic announce + RPC)
3. Create RemoteProxy.lua (method stub generator)
4. Create PeripheralClient.lua (discovery + RPC calls)

### Phase 2: Integration
5. Create RemotePeripheral.lua (drop-in replacement)
6. Modify AEInterface to use RemotePeripheral
7. Add peripheral client init to Kernel

### Phase 3: Headless Mode
8. Create headless.lua mode
9. Auto-detect mode in start.lua
10. Terminal UI for headless status

### Phase 4: Optimization (Future)
11. Implement caching layer (reduce network calls)
12. Add subscription/push updates (real-time data)
13. Connection health monitoring
14. Reconnection logic

## Testing Checklist

- [ ] Local peripheral still works (no regression)
- [ ] Remote peripheral discovered via ender modem
- [ ] RPC calls return correct data
- [ ] Method calls with arguments work
- [ ] Error handling on disconnect
- [ ] Reconnection after host restart
- [ ] Multiple hosts with same peripheral type
- [ ] Cache invalidation works correctly
- [ ] Subscription updates received
- [ ] Headless mode boots correctly
