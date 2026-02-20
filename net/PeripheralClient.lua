-- PeripheralClient.lua
-- Discovers and consumes remote peripherals over ender modem
-- Creates proxy objects that behave like local peripherals

local Protocol = mpm('net/Protocol')
local RemoteProxy = mpm('net/RemoteProxy')
local Yield = mpm('utils/Yield')

local PeripheralClient = {}
PeripheralClient.__index = PeripheralClient

-- Create a new peripheral client
-- @param channel Channel instance for network communication
function PeripheralClient.new(channel)
    local self = setmetatable({}, PeripheralClient)

    self.channel = channel
    self.remotePeripherals = {}  -- {key -> {key, name, displayName, hostId, hostComputerName, type, methods, proxy}}
    self.remoteByName = {}       -- {name -> {key1, key2, ...}}
    self.remoteNameAlias = {}    -- {name -> preferredKey}
    self.hostPeripheralKeys = {} -- {hostId -> { [key] = true }}
    self.hostComputers = {}      -- {hostId -> {computerId, computerName}}
    self.pendingRequests = {}    -- {requestId -> {callback, timeout}}

    return self
end

local function makeRemoteKey(hostId, name)
    return tostring(hostId) .. "::" .. tostring(name)
end

local function sortRemoteKeys(keys, remotePeripherals)
    table.sort(keys, function(a, b)
        local ai = remotePeripherals[a]
        local bi = remotePeripherals[b]
        if not ai then return false end
        if not bi then return true end
        local ah = tonumber(ai.hostId) or math.huge
        local bh = tonumber(bi.hostId) or math.huge
        if ah ~= bh then
            return ah < bh
        end
        return tostring(a) < tostring(b)
    end)
end

local function sortedRemoteKeys(remotePeripherals)
    local keys = {}
    for key in pairs(remotePeripherals) do
        table.insert(keys, key)
    end
    sortRemoteKeys(keys, remotePeripherals)
    return keys
end

function PeripheralClient:rebuildNameIndexes()
    self.remoteByName = {}
    self.remoteNameAlias = {}

    for key, info in pairs(self.remotePeripherals) do
        local name = info.name
        if name and name ~= "" then
            self.remoteByName[name] = self.remoteByName[name] or {}
            table.insert(self.remoteByName[name], key)
        end
    end

    for name, keys in pairs(self.remoteByName) do
        sortRemoteKeys(keys, self.remotePeripherals)
        self.remoteNameAlias[name] = keys[1]
    end
end

function PeripheralClient:removeHostRemotes(hostId)
    local keys = self.hostPeripheralKeys[hostId]
    if not keys then
        return
    end

    for key in pairs(keys) do
        self.remotePeripherals[key] = nil
    end
    self.hostPeripheralKeys[hostId] = nil
    self:rebuildNameIndexes()
end

function PeripheralClient:resolveInfo(nameOrKey)
    if not nameOrKey then
        return nil
    end

    local info = self.remotePeripherals[nameOrKey]
    if info then
        return info
    end

    local aliasKey = self.remoteNameAlias[nameOrKey]
    if aliasKey then
        return self.remotePeripherals[aliasKey]
    end

    return nil
end

function PeripheralClient:getDisplayName(nameOrKey)
    local info = self:resolveInfo(nameOrKey)
    if not info then
        return nil
    end
    return info.displayName or info.key or info.name
end

-- Register handlers for incoming messages
function PeripheralClient:registerHandlers()
    if not self.channel then return end

    -- Handle peripheral announcements
    self.channel:on(Protocol.MessageType.PERIPH_ANNOUNCE, function(senderId, msg)
        self:handleAnnounce(senderId, msg)
    end)

    -- Handle peripheral list response
    self.channel:on(Protocol.MessageType.PERIPH_LIST, function(senderId, msg)
        self:handlePeriphList(senderId, msg)
    end)

    -- Handle call results
    self.channel:on(Protocol.MessageType.PERIPH_RESULT, function(senderId, msg)
        self:handleResult(senderId, msg)
    end)

    -- Handle call errors
    self.channel:on(Protocol.MessageType.PERIPH_ERROR, function(senderId, msg)
        self:handleError(senderId, msg)
    end)
end

-- Handle peripheral announcement from host
function PeripheralClient:handleAnnounce(senderId, msg)
    local data = msg.data
    if not data or not data.peripherals then return end

    -- Store computer info
    self.hostComputers[senderId] = {
        computerId = data.computerId,
        computerName = data.computerName
    }

    self:removeHostRemotes(senderId)

    -- Register peripherals
    for _, pInfo in ipairs(data.peripherals) do
        self:registerRemote(senderId, pInfo.name, pInfo.type, pInfo.methods, data.computerName)
    end
end

-- Handle peripheral list response
function PeripheralClient:handlePeriphList(senderId, msg)
    local data = msg.data
    if not data or not data.peripherals then
        return
    end

    -- Refresh computer metadata when available (discover responses may arrive before announce).
    if data.computerId or data.computerName then
        self.hostComputers[senderId] = {
            computerId = data.computerId or senderId,
            computerName = data.computerName
        }
    end

    self:removeHostRemotes(senderId)

    -- Register peripherals
    for _, pInfo in ipairs(data.peripherals) do
        self:registerRemote(senderId, pInfo.name, pInfo.type, pInfo.methods)
    end

    -- Resolve pending request if any
    if msg.requestId and self.pendingRequests[msg.requestId] then
        local req = self.pendingRequests[msg.requestId]
        self.pendingRequests[msg.requestId] = nil
        if req.callback then
            req.callback(data.peripherals, nil)
        end
    end
end

-- Handle call result
function PeripheralClient:handleResult(senderId, msg)
    if not msg.requestId then return end

    local req = self.pendingRequests[msg.requestId]
    if req then
        self.pendingRequests[msg.requestId] = nil
        if req.callback then
            req.callback(msg.data.results, nil)
        end
    end
end

-- Handle call error
function PeripheralClient:handleError(senderId, msg)
    if not msg.requestId then return end

    local req = self.pendingRequests[msg.requestId]
    if req then
        self.pendingRequests[msg.requestId] = nil
        if req.callback then
            req.callback(nil, msg.data.error)
        end
    end
end

-- Register a remote peripheral
function PeripheralClient:registerRemote(hostId, name, pType, methods)
    local key = makeRemoteKey(hostId, name)
    local hostComputer = self.hostComputers[hostId]
    local hostComputerName = hostComputer and hostComputer.computerName or nil
    local displayName = hostComputerName and (name .. " @ " .. hostComputerName) or (name .. " @ #" .. tostring(hostId))

    -- Create proxy
    local proxy = RemoteProxy.create(self, hostId, name, pType, methods, key, displayName)

    self.remotePeripherals[key] = {
        key = key,
        name = name,
        displayName = displayName,
        hostId = hostId,
        hostComputerName = hostComputerName,
        type = pType,
        methods = methods,
        proxy = proxy
    }

    self.hostPeripheralKeys[hostId] = self.hostPeripheralKeys[hostId] or {}
    self.hostPeripheralKeys[hostId][key] = true
    self:rebuildNameIndexes()
end

-- Discover remote peripherals (broadcast and wait)
-- Called during boot (before parallel starts) - uses channel:poll() directly.
-- @param timeout Seconds to wait for responses
-- @return Number of peripherals discovered
function PeripheralClient:discover(timeout)
    timeout = timeout or 3

    if not self.channel then
        return 0
    end

    -- Register handlers if not already
    self:registerHandlers()

    -- Send discovery request
    local msg = Protocol.createPeriphDiscover()
    self.channel:broadcast(msg)

    -- Poll for responses
    -- NOTE: This is safe during boot (single coroutine, no parallel contention).
    -- During parallel execution, use discoverAsync() instead.
    local deadline = os.epoch("utc") + (timeout * 1000)
    while os.epoch("utc") < deadline do
        self.channel:poll(0.1)
        Yield.yield()  -- Allow other events to process
    end

    return self:getCount()
end

-- Non-blocking discovery request (safe during parallel execution)
-- Broadcasts a discover message; responses are handled by KernelNetwork loop
-- @return void
function PeripheralClient:discoverAsync()
    if not self.channel then return end

    local msg = Protocol.createPeriphDiscover()
    self.channel:broadcast(msg)
end

-- Get count of known remote peripherals
function PeripheralClient:getCount()
    local count = 0
    for _ in pairs(self.remotePeripherals) do
        count = count + 1
    end
    return count
end

-- Find a remote peripheral by type
-- @param pType Peripheral type to find
-- @return Proxy or nil
function PeripheralClient:find(pType)
    for _, key in ipairs(sortedRemoteKeys(self.remotePeripherals)) do
        local info = self.remotePeripherals[key]
        if info.type == pType then
            return info.proxy
        end
    end
    return nil
end

-- Find all remote peripherals by type
-- @param pType Peripheral type to find
-- @return Array of proxies
function PeripheralClient:findAll(pType)
    local results = {}
    for _, key in ipairs(sortedRemoteKeys(self.remotePeripherals)) do
        local info = self.remotePeripherals[key]
        if info.type == pType then
            table.insert(results, info.proxy)
        end
    end
    return results
end

-- Wrap a remote peripheral by name
-- @param name Peripheral name
-- @return Proxy or nil
function PeripheralClient:wrap(name)
    local info = self:resolveInfo(name)
    if info then
        return info.proxy
    end
    return nil
end

-- Get names of all remote peripherals
function PeripheralClient:getNames()
    local names = {}
    local nameIndex = {}

    for rawName, keys in pairs(self.remoteByName) do
        if #keys == 1 then
            nameIndex[rawName] = true
        else
            for _, key in ipairs(keys) do
                nameIndex[key] = true
            end
        end
    end

    for name in pairs(nameIndex) do
        table.insert(names, name)
    end

    table.sort(names)
    return names
end

-- Get type of a remote peripheral
function PeripheralClient:getType(name)
    local info = self:resolveInfo(name)
    if info then
        return info.type
    end
    return nil
end

-- Check if peripheral has type
function PeripheralClient:hasType(name, pType)
    local info = self:resolveInfo(name)
    if info then
        return info.type == pType
    end
    return nil
end

-- Get methods of a remote peripheral
function PeripheralClient:getMethods(name)
    local info = self:resolveInfo(name)
    if info then
        return info.methods
    end
    return nil
end

-- Call a method on a remote peripheral (blocking)
-- @param hostId Host computer ID
-- @param peripheralName Peripheral name
-- @param methodName Method to call
-- @param args Arguments array
-- @param timeout Timeout in seconds
-- @return results, error
--
-- IMPORTANT: This runs inside view coroutines (parallel architecture).
-- We MUST NOT call channel:poll() here because rednet_message events
-- are delivered to the KernelNetwork coroutine's event queue, not ours.
-- Instead, we send the request and yield-wait for the callback to be
-- triggered by the network loop's channel:poll().
function PeripheralClient:call(hostId, peripheralName, methodName, args, timeout)
    timeout = timeout or 2

    if not self.channel then
        return nil, "not_connected"
    end

    -- Create call message
    local msg = Protocol.createPeriphCall(peripheralName, methodName, args)

    -- Set up response handling via shared state
    -- The KernelNetwork loop's channel:poll() will trigger PERIPH_RESULT handler
    -- which calls this callback, setting done=true
    local state = { done = false, result = nil, err = nil }

    self.pendingRequests[msg.requestId] = {
        callback = function(r, e)
            state.result = r
            state.err = e
            state.done = true
        end,
        timeout = os.epoch("utc") + (timeout * 1000)
    }

    -- Send request
    self.channel:send(hostId, msg)

    -- Wait for response by yielding
    -- The network coroutine processes incoming messages and triggers our callback
    -- We just need to yield to give it CPU time, then check the flag
    local deadline = os.epoch("utc") + (timeout * 1000)
    while not state.done and os.epoch("utc") < deadline do
        -- Cooperative yield without discarding queued events.
        Yield.yield()
    end

    -- Clean up if timed out
    if not state.done then
        self.pendingRequests[msg.requestId] = nil
        return nil, "timeout"
    end

    return state.result, state.err
end

-- Fire-and-forget RPC call (non-blocking)
-- Sends the request and registers a callback that will be invoked by the
-- KernelNetwork loop when the response arrives. Does NOT block the caller.
-- Used by RemoteProxy cache-refresh to update cached values asynchronously.
-- @param hostId Host computer ID
-- @param peripheralName Peripheral name
-- @param methodName Method to call
-- @param args Arguments array
-- @param callback function(results, error) called when response arrives
-- @param timeout Timeout in seconds for expiring the pending request
function PeripheralClient:callAsync(hostId, peripheralName, methodName, args, callback, timeout)
    timeout = timeout or 5

    if not self.channel then
        if callback then callback(nil, "not_connected") end
        return
    end

    local msg = Protocol.createPeriphCall(peripheralName, methodName, args)

    self.pendingRequests[msg.requestId] = {
        callback = callback or function() end,
        timeout = os.epoch("utc") + (timeout * 1000)
    }

    self.channel:send(hostId, msg)
end

-- Rediscover a specific peripheral
-- During parallel execution, broadcasts async and waits briefly for the
-- KernelNetwork loop to process responses.
-- @param name Peripheral name to find
-- @return info table or nil
function PeripheralClient:rediscover(name)
    -- Broadcast discovery request (handled by network loop)
    self:discoverAsync()

    -- Wait briefly for network loop to process PERIPH_LIST responses
    local deadline = os.epoch("utc") + 2000
    while os.epoch("utc") < deadline do
        local info = self:resolveInfo(name)
        if info then
            return info
        end
        Yield.yield()
    end

    return self:resolveInfo(name)
end

-- Clean up expired pending requests (prevents memory leaks from async calls)
-- Called periodically by KernelNetwork loop
function PeripheralClient:cleanupExpired()
    local now = os.epoch("utc")
    local expired = {}
    for reqId, req in pairs(self.pendingRequests) do
        if req.timeout and now > req.timeout then
            table.insert(expired, reqId)
        end
    end
    for _, reqId in ipairs(expired) do
        local req = self.pendingRequests[reqId]
        self.pendingRequests[reqId] = nil
        -- Notify callback of timeout so proxy cache can handle it
        if req and req.callback then
            pcall(req.callback, nil, "timeout")
        end
    end
end

-- Check if a peripheral is available
function PeripheralClient:isPresent(name)
    return self:resolveInfo(name) ~= nil
end

-- Clear all known peripherals
function PeripheralClient:clear()
    self.remotePeripherals = {}
    self.remoteByName = {}
    self.remoteNameAlias = {}
    self.hostPeripheralKeys = {}
    self.hostComputers = {}
end

return PeripheralClient
