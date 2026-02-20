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
    peripherals = {},          -- {name -> {type, methods, peripheral}}

    -- Core functions
    scan(),                    -- Discover local peripherals
    announce(),                -- Broadcast availability
    handleCall(sender, msg),   -- Execute RPC and return result
    handleDiscover(sender, msg),
}
```

**Peripheral Announcement Message:**
```lua
{
    type = "periph_announce",
    data = {
        computerId = "computer_123",
        computerName = "Storage Room",
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
    remoteNameAlias = {},      -- {name -> preferredKey}
    pendingRequests = {},      -- {requestId -> {callback, timeout}}

    -- Core functions
    discover(timeout),         -- Find remote peripherals
    find(type),                -- Find peripheral by type (local or remote)
    wrap(name),                -- Get proxy for peripheral
    call(hostId, name, method, args, timeout),   -- Blocking RPC call
    callAsync(hostId, name, method, args, callback, timeout),
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
            local args = {...}
            local results = client:call(hostId, peripheralName, methodName, args)
            if results then return table.unpack(results) end
            return nil
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

    -- Type-aware local-first behavior: local match wins, but local mismatch
    -- does not mask a valid remote peripheral with the same name.
    hasType = function(name, pType)
        local localPresent = peripheral.isPresent(name)
        if localPresent and peripheral.hasType(name, pType) then
            return true
        end
        if RemotePeripheral.client then
            local remoteMatch = RemotePeripheral.client:hasType(name, pType)
            if remoteMatch ~= nil then return remoteMatch end
        end
        if localPresent then return false end
        return nil
    end,

    -- Get all peripherals (local + remote)
    getNames = function()
        local names = peripheral.getNames()
        if RemotePeripheral.client then
            for _, name in ipairs(RemotePeripheral.client:getNames()) do
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

## Caching Strategy

### Proxy-Local Cache

```lua
proxy._name = "42::left"    -- stable identity
proxy._cache = {
    ["getItems"] = {
        results = {...},
        timestamp = 1234567890
    },
    ["getEnergy_0"] = {
        results = {...},
        timestamp = 1234567890
    }
}
```

`RemoteProxy` owns read-method cache state. `PeripheralClient` tracks remote
identity/routing and pending RPC requests, not a shared value cache keyed by
raw peripheral name.

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
-- In KernelNetwork.initialize()
local peripheralClient = PeripheralClient.new(channel)
peripheralClient:registerHandlers()
RemotePeripheral.setClient(peripheralClient)
peripheralClient:discoverAsync()
```

### Terminal-Only Runtime (0 Monitors)

In the unified architecture, `shelfos/start.lua` always boots `Kernel.lua` for non-pocket computers.
When there are zero monitors, Kernel still initializes network lifecycle, starts `PeripheralHost` and
`PeripheralClient`, and runs terminal dashboard + menu loops without monitor render coroutines.

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
├── PeripheralHost.lua   # serves peripherals
├── PeripheralClient.lua # consumes remote peripherals
├── RemoteProxy.lua      # proxy object generator + cache
└── RemotePeripheral.lua # drop-in peripheral replacement

shelfos/
├── core/
│   ├── Kernel.lua       # unified runtime (monitor + terminal-only)
│   └── KernelNetwork.lua # shared network lifecycle
└── start.lua            # pocket redirect or unified kernel boot
```

## Implementation Order

### Current Priorities
1. Keep key-based identity consistent (`<hostId>::<name>`) across all callsites
2. Preserve local-first behavior while preventing remote masking on type mismatch
3. Maintain shared host/unhost lifecycle via `KernelNetwork`
4. Extend test coverage for collisions, ordering, and fallback edge cases

## Testing Checklist

- [ ] Local peripheral still works (no regression)
- [ ] Remote peripheral discovered via ender modem
- [ ] RPC calls return correct data
- [ ] Method calls with arguments work
- [ ] Error handling on disconnect
- [ ] Reconnection after host restart
- [ ] Multiple hosts with same peripheral names (`left`, `right`, etc.) do not collide
- [ ] Bare-name vs key-based lookup behavior is deterministic and documented
- [ ] Local type mismatch does not mask valid remote peripheral (`hasType` path)
- [ ] Zero-monitor terminal runtime boots correctly
