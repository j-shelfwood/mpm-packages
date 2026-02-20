local Protocol = mpm('net/Protocol')
local Yield = mpm('utils/Yield')

local PeripheralDiscovery = {}

function PeripheralDiscovery.init(client)
    client.hostDiscoverRequests = {}
    client.discoverRequestHost = {}
end

function PeripheralDiscovery.requestDiscoverFromHost(client, hostId, timeout)
    if not client.channel then
        return false
    end

    local existingId = client.hostDiscoverRequests[hostId]
    if existingId and client.pendingRequests[existingId] then
        return false
    end

    local msg = Protocol.createPeriphDiscover()
    local requestId = msg.requestId
    client.hostDiscoverRequests[hostId] = requestId
    client.discoverRequestHost[requestId] = hostId

    client.pendingRequests[requestId] = {
        callbacks = {},
        timeout = os.epoch("utc") + ((timeout or 3) * 1000)
    }

    client.channel:send(hostId, msg)
    return true
end

function PeripheralDiscovery.registerHandlers(client)
    if not client.channel then
        return
    end

    client.channel:on(Protocol.MessageType.PERIPH_ANNOUNCE, function(senderId, msg)
        client:handleAnnounce(senderId, msg)
    end)

    client.channel:on(Protocol.MessageType.PERIPH_LIST, function(senderId, msg)
        client:handlePeriphList(senderId, msg)
    end)

    client.channel:on(Protocol.MessageType.PERIPH_RESULT, function(senderId, msg)
        client:handleResult(senderId, msg)
    end)

    client.channel:on(Protocol.MessageType.PERIPH_ERROR, function(senderId, msg)
        client:handleError(senderId, msg)
    end)
end

function PeripheralDiscovery.handleAnnounce(client, senderId, msg)
    local data = msg.data
    if not data then
        return
    end

    client.hostComputers[senderId] = {
        computerId = data.computerId,
        computerName = data.computerName
    }

    if data.peripherals then
        client:removeHostRemotes(senderId)
        for _, pInfo in ipairs(data.peripherals) do
            client:registerRemote(senderId, pInfo.name, pInfo.type, pInfo.methods, data.computerName, true)
        end
        client:rebuildNameIndexes()
        if data.stateHash then
            client.hostStateHashes[senderId] = data.stateHash
        end
        return
    end

    local stateHash = data.stateHash
    local previousHash = client.hostStateHashes[senderId]
    local hasHostRemotes = client.hostPeripheralKeys[senderId] ~= nil

    if stateHash then
        client.hostStateHashes[senderId] = stateHash
    end

    local needsDiscover = (not hasHostRemotes) or (stateHash and stateHash ~= previousHash)
    if needsDiscover then
        PeripheralDiscovery.requestDiscoverFromHost(client, senderId, 3)
    end
end

function PeripheralDiscovery.handlePeriphList(client, senderId, msg)
    local data = msg.data
    if not data or not data.peripherals then
        return
    end

    if data.computerId or data.computerName then
        client.hostComputers[senderId] = {
            computerId = data.computerId or senderId,
            computerName = data.computerName
        }
    end

    client:removeHostRemotes(senderId)

    for _, pInfo in ipairs(data.peripherals) do
        client:registerRemote(senderId, pInfo.name, pInfo.type, pInfo.methods, nil, true)
    end
    client:rebuildNameIndexes()

    local activeDiscoverReq = client.hostDiscoverRequests[senderId]
    if activeDiscoverReq then
        client.hostDiscoverRequests[senderId] = nil
        client.discoverRequestHost[activeDiscoverReq] = nil
        if activeDiscoverReq ~= msg.requestId and client.pendingRequests[activeDiscoverReq] then
            client:resolvePending(activeDiscoverReq, data.peripherals, nil)
        end
    end

    local reqHost = msg.requestId and client.discoverRequestHost[msg.requestId] or nil
    if reqHost ~= nil then
        client.hostDiscoverRequests[reqHost] = nil
        client.discoverRequestHost[msg.requestId] = nil
    end

    if msg.requestId and client.pendingRequests[msg.requestId] then
        client:resolvePending(msg.requestId, data.peripherals, nil)
    end
end

function PeripheralDiscovery.discover(client, timeout)
    timeout = timeout or 3

    if not client.channel then
        return 0
    end

    client:registerHandlers()

    local msg = Protocol.createPeriphDiscover()
    client.channel:broadcast(msg)

    local deadline = os.epoch("utc") + (timeout * 1000)
    while os.epoch("utc") < deadline do
        client.channel:poll(0.1)
        Yield.yield()
    end

    return client:getCount()
end

function PeripheralDiscovery.discoverAsync(client)
    if not client.channel then
        return
    end

    local msg = Protocol.createPeriphDiscover()
    client.channel:broadcast(msg)
end

function PeripheralDiscovery.rediscover(client, name)
    client:discoverAsync()

    local deadline = os.epoch("utc") + 2000
    while os.epoch("utc") < deadline do
        local info = client:resolveInfo(name)
        if info then
            return info
        end
        Yield.yield()
    end

    return client:resolveInfo(name)
end

function PeripheralDiscovery.clear(client)
    client.hostDiscoverRequests = {}
    client.discoverRequestHost = {}
end

return PeripheralDiscovery
