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
    self.remotePeripherals = {}  -- {name -> {hostId, type, methods, proxy}}
    self.hostComputers = {}      -- {hostId -> {computerId, computerName}}
    self.pendingRequests = {}    -- {requestId -> {callback, timeout}}

    return self
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

    -- Register peripherals
    for _, pInfo in ipairs(data.peripherals) do
        self:registerRemote(senderId, pInfo.name, pInfo.type, pInfo.methods)
    end
end

-- Handle peripheral list response
function PeripheralClient:handlePeriphList(senderId, msg)
    local data = msg.data
    if not data or not data.peripherals then
        return
    end

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
    -- Create proxy
    local proxy = RemoteProxy.create(self, hostId, name, pType, methods)

    self.remotePeripherals[name] = {
        hostId = hostId,
        type = pType,
        methods = methods,
        proxy = proxy
    }
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
    for name, info in pairs(self.remotePeripherals) do
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
    for name, info in pairs(self.remotePeripherals) do
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
    local info = self.remotePeripherals[name]
    if info then
        return info.proxy
    end
    return nil
end

-- Get names of all remote peripherals
function PeripheralClient:getNames()
    local names = {}
    for name, _ in pairs(self.remotePeripherals) do
        table.insert(names, name)
    end
    return names
end

-- Get type of a remote peripheral
function PeripheralClient:getType(name)
    local info = self.remotePeripherals[name]
    if info then
        return info.type
    end
    return nil
end

-- Check if peripheral has type
function PeripheralClient:hasType(name, pType)
    local info = self.remotePeripherals[name]
    if info then
        return info.type == pType
    end
    return nil
end

-- Get methods of a remote peripheral
function PeripheralClient:getMethods(name)
    local info = self.remotePeripherals[name]
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
        -- Use os.pullEvent with a short timer to yield control
        -- This allows the parallel scheduler to run the network coroutine
        local timer = os.startTimer(0.05)
        os.pullEvent("timer")
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
        if self.remotePeripherals[name] then
            return self.remotePeripherals[name]
        end
        local timer = os.startTimer(0.1)
        os.pullEvent("timer")
    end

    return self.remotePeripherals[name]
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
    return self.remotePeripherals[name] ~= nil
end

-- Clear all known peripherals
function PeripheralClient:clear()
    self.remotePeripherals = {}
    self.hostComputers = {}
end

return PeripheralClient
