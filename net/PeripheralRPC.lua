local Protocol = mpm('net/Protocol')
local Yield = mpm('utils/Yield')

local PeripheralRPC = {}

local function serializeArgs(args)
    if type(args) ~= "table" then
        return tostring(args)
    end
    local ok, encoded = pcall(textutils.serialize, args)
    if ok and type(encoded) == "string" then
        return encoded
    end
    return tostring(args)
end

local function makeCallCoalesceKey(hostId, peripheralName, methodName, args, options)
    return table.concat({
        tostring(hostId),
        tostring(peripheralName),
        tostring(methodName),
        serializeArgs(args or {}),
        serializeArgs(options or {})
    }, "|")
end

local function addPendingCallback(req, callback)
    if type(callback) ~= "function" then
        return
    end
    req.callbacks = req.callbacks or {}
    table.insert(req.callbacks, callback)
end

function PeripheralRPC.init(client)
    client.pendingRequests = {}
    client.inflightByCallKey = {}
end

function PeripheralRPC.resolvePending(client, requestId, result, err, meta)
    local req = client.pendingRequests[requestId]
    if not req then
        return
    end

    client.pendingRequests[requestId] = nil
    if req.coalesceKey and client.inflightByCallKey[req.coalesceKey] == requestId then
        client.inflightByCallKey[req.coalesceKey] = nil
    end

    local callbacks = req.callbacks or {}
    for i = 1, #callbacks do
        pcall(callbacks[i], result, err, meta)
    end
end

function PeripheralRPC.handleResult(client, senderId, msg)
    if not msg.requestId then
        return
    end
    local data = msg.data or {}
    PeripheralRPC.resolvePending(client, msg.requestId, data.results, nil, data.meta)
end

function PeripheralRPC.handleError(client, senderId, msg)
    if not msg.requestId then
        return
    end
    PeripheralRPC.resolvePending(client, msg.requestId, nil, msg.data and msg.data.error or "unknown_error")
end

function PeripheralRPC.call(client, hostId, peripheralName, methodName, args, timeout, options)
    timeout = timeout or 2

    if not client.channel then
        return nil, "not_connected"
    end

    local state = { done = false, result = nil, err = nil }
    local callback = function(r, e, m)
        state.result = r
        state.err = e
        state.meta = m
        state.done = true
    end

    local callKey = makeCallCoalesceKey(hostId, peripheralName, methodName, args, options)
    local requestId = client.inflightByCallKey[callKey]
    local pending = requestId and client.pendingRequests[requestId] or nil
    local deadline = os.epoch("utc") + (timeout * 1000)

    if pending then
        addPendingCallback(pending, callback)
        pending.timeout = math.max(pending.timeout or deadline, deadline)
    else
        local msg = Protocol.createPeriphCall(peripheralName, methodName, args)
        client.inflightByCallKey[callKey] = msg.requestId
        client.pendingRequests[msg.requestId] = {
            callbacks = { callback },
            timeout = deadline,
            coalesceKey = callKey
        }
        if type(options) == "table" then
            msg.data.options = options
        end
        client.channel:send(hostId, msg)
    end

    while not state.done and os.epoch("utc") < deadline do
        Yield.yield()
    end

    if not state.done then
        return nil, "timeout"
    end

    return state.result, state.err, state.meta
end

function PeripheralRPC.callAsync(client, hostId, peripheralName, methodName, args, callback, timeout, options)
    timeout = timeout or 5

    if not client.channel then
        if callback then callback(nil, "not_connected") end
        return
    end

    local callKey = makeCallCoalesceKey(hostId, peripheralName, methodName, args, options)
    local requestId = client.inflightByCallKey[callKey]
    local pending = requestId and client.pendingRequests[requestId] or nil
    local cb = callback or function() end
    local deadline = os.epoch("utc") + (timeout * 1000)

    if pending then
        addPendingCallback(pending, cb)
        pending.timeout = math.max(pending.timeout or deadline, deadline)
        return
    end

    local msg = Protocol.createPeriphCall(peripheralName, methodName, args)
    client.inflightByCallKey[callKey] = msg.requestId
    client.pendingRequests[msg.requestId] = {
        callbacks = { cb },
        timeout = deadline,
        coalesceKey = callKey
    }

    if type(options) == "table" then
        msg.data.options = options
    end
    client.channel:send(hostId, msg)
end

function PeripheralRPC.cleanupExpired(client)
    local now = os.epoch("utc")
    local expired = {}
    for reqId, req in pairs(client.pendingRequests) do
        if req.timeout and now > req.timeout then
            table.insert(expired, reqId)
        end
    end
    for _, reqId in ipairs(expired) do
        local reqHost = client.discoverRequestHost[reqId]
        if reqHost ~= nil then
            client.hostDiscoverRequests[reqHost] = nil
            client.discoverRequestHost[reqId] = nil
        end
        PeripheralRPC.resolvePending(client, reqId, nil, "timeout")
    end
end

function PeripheralRPC.clear(client)
    client.pendingRequests = {}
    client.inflightByCallKey = {}
end

return PeripheralRPC
