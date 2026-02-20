-- PeripheralClient.lua
-- Facade for remote peripheral discovery, registry, and RPC calls.

local PeripheralDiscovery = mpm('net/PeripheralDiscovery')
local PeripheralRPC = mpm('net/PeripheralRPC')
local PeripheralRegistry = mpm('net/PeripheralRegistry')

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

function PeripheralClient:registerRemote(hostId, name, pType, methods, computerName, deferIndexRebuild)
    PeripheralRegistry.registerRemote(self, hostId, name, pType, methods, computerName, deferIndexRebuild)
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
