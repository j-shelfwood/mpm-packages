-- PeripheralClient.lua
-- Facade for remote peripheral discovery, registry, and RPC calls.

local PeripheralDiscovery = mpm('net/PeripheralDiscovery')
local PeripheralRPC = mpm('net/PeripheralRPC')
local PeripheralRegistry = mpm('net/PeripheralRegistry')
local Protocol = mpm('net/Protocol')

local PeripheralClient = {}
PeripheralClient.__index = PeripheralClient

function PeripheralClient.new(channel)
    local self = setmetatable({}, PeripheralClient)
    self.channel = channel

    PeripheralRegistry.init(self)
    PeripheralDiscovery.init(self)
    PeripheralRPC.init(self)

    return self
end

function PeripheralClient:rebuildNameIndexes()
    PeripheralRegistry.rebuildNameIndexes(self)
end

function PeripheralClient:removeHostRemotes(hostId)
    PeripheralRegistry.removeHostRemotes(self, hostId)
end

function PeripheralClient:resolvePending(requestId, result, err, meta)
    PeripheralRPC.resolvePending(self, requestId, result, err, meta)
end

function PeripheralClient:requestDiscoverFromHost(hostId, timeout)
    return PeripheralDiscovery.requestDiscoverFromHost(self, hostId, timeout)
end

function PeripheralClient:resolveInfo(nameOrKey)
    return PeripheralRegistry.resolveInfo(self, nameOrKey)
end

function PeripheralClient:getDisplayName(nameOrKey)
    return PeripheralRegistry.getDisplayName(self, nameOrKey)
end

function PeripheralClient:registerHandlers()
    PeripheralDiscovery.registerHandlers(self)

    if self.channel then
        self.channel:on(Protocol.MessageType.PERIPH_STATE_PUSH, function(senderId, msg)
            self:handleStatePush(senderId, msg)
        end)
    end
end

function PeripheralClient:handleAnnounce(senderId, msg)
    PeripheralDiscovery.handleAnnounce(self, senderId, msg)
end

function PeripheralClient:handlePeriphList(senderId, msg)
    PeripheralDiscovery.handlePeriphList(self, senderId, msg)
end

function PeripheralClient:handleResult(senderId, msg)
    PeripheralRPC.handleResult(self, senderId, msg)
end

function PeripheralClient:handleError(senderId, msg)
    PeripheralRPC.handleError(self, senderId, msg)
end

function PeripheralClient:handleStatePush(senderId, msg)
    local data = msg.data or {}
    local hostId = data.hostId or senderId
    local key = tostring(hostId) .. "::" .. tostring(data.peripheral or "")
    local info = self.remotePeripherals and self.remotePeripherals[key] or nil
    if info and info.proxy and type(info.proxy._applyStatePush) == "function" then
        info.proxy:_applyStatePush(data.method, data.results, data.meta, data.args)
    end
    local eventName = data.event or "remote_periph_update"
    pcall(os.queueEvent, eventName, data.peripheral, data.method, data.results, data.meta, hostId)
end

function PeripheralClient:registerRemote(hostId, name, pType, methods, activity, computerName, deferIndexRebuild)
    PeripheralRegistry.registerRemote(self, hostId, name, pType, methods, activity, computerName, deferIndexRebuild)
end

function PeripheralClient:discover(timeout)
    return PeripheralDiscovery.discover(self, timeout)
end

function PeripheralClient:discoverAsync()
    PeripheralDiscovery.discoverAsync(self)
end

function PeripheralClient:getCount()
    return PeripheralRegistry.getCount(self)
end

function PeripheralClient:find(pType)
    return PeripheralRegistry.find(self, pType)
end

function PeripheralClient:findAll(pType)
    return PeripheralRegistry.findAll(self, pType)
end

function PeripheralClient:wrap(name)
    return PeripheralRegistry.wrap(self, name)
end

function PeripheralClient:getNames()
    return PeripheralRegistry.getNames(self)
end

function PeripheralClient:getType(name)
    return PeripheralRegistry.getType(self, name)
end

function PeripheralClient:hasType(name, pType)
    return PeripheralRegistry.hasType(self, name, pType)
end

function PeripheralClient:getMethods(name)
    return PeripheralRegistry.getMethods(self, name)
end

function PeripheralClient:call(hostId, peripheralName, methodName, args, timeout, options)
    return PeripheralRPC.call(self, hostId, peripheralName, methodName, args, timeout, options)
end

function PeripheralClient:callAsync(hostId, peripheralName, methodName, args, callback, timeout, options)
    PeripheralRPC.callAsync(self, hostId, peripheralName, methodName, args, callback, timeout, options)
end

function PeripheralClient:subscribe(hostId, peripheralName, methodName, args, intervalMs, eventName)
    if not self.channel then
        return false, "not_connected"
    end
    local msg = Protocol.createPeriphSubscribe(peripheralName, methodName, args, intervalMs, eventName)
    self.channel:send(hostId, msg)
    return true, nil
end

function PeripheralClient:unsubscribe(hostId, peripheralName, methodName, args)
    if not self.channel then
        return false, "not_connected"
    end
    local msg = Protocol.createPeriphUnsubscribe(peripheralName, methodName, args)
    self.channel:send(hostId, msg)
    return true, nil
end

function PeripheralClient:rediscover(name)
    return PeripheralDiscovery.rediscover(self, name)
end

function PeripheralClient:cleanupExpired()
    PeripheralRPC.cleanupExpired(self)
end

function PeripheralClient:isPresent(name)
    return PeripheralRegistry.isPresent(self, name)
end

function PeripheralClient:clear()
    PeripheralRegistry.clear(self)
    PeripheralDiscovery.clear(self)
    PeripheralRPC.clear(self)
end

return PeripheralClient
