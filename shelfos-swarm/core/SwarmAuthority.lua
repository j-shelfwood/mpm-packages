-- SwarmAuthority.lua
-- Facade for swarm identity, registry, and pairing session coordination.

local Envelope = mpm('crypto/Envelope')
local SwarmIdentity = mpm('shelfos-swarm/core/SwarmIdentity')
local SwarmRegistry = mpm('shelfos-swarm/core/SwarmRegistry')
local PairingSession = mpm('shelfos-swarm/core/PairingSession')

local SwarmAuthority = {}
SwarmAuthority.__index = SwarmAuthority

local REGISTRY_PATH = "/swarm_registry.dat"
local IDENTITY_PATH = "/swarm_identity.dat"

function SwarmAuthority.new()
    local self = setmetatable({}, SwarmAuthority)
    self.registry = SwarmRegistry.new(REGISTRY_PATH)
    self.identity = nil
    self.initialized = false
    self.pendingPairings = {}

    return self
end

function SwarmAuthority:exists()
    return SwarmIdentity.exists(IDENTITY_PATH) and self.registry:exists()
end

function SwarmAuthority:init()
    if self:exists() then
        return self:load()
    end
    return false, false
end

function SwarmAuthority:createSwarm(swarmName)
    self.identity = SwarmIdentity.create(self.registry, swarmName)
    self.registry:initSwarm(self.identity.id, self.identity.secret)

    local ok = self:save()
    if not ok then
        return false, nil
    end

    self.initialized = true
    return true, self.identity.id
end

function SwarmAuthority:load()
    self.identity = SwarmIdentity.load(IDENTITY_PATH)
    if not self.identity then
        return false, false
    end

    local regOk = self.registry:load()
    if not regOk then
        return false, false
    end

    self.initialized = true
    return true, false
end

function SwarmAuthority:save()
    if not SwarmIdentity.save(IDENTITY_PATH, self.identity) then
        return false
    end

    return self.registry:save()
end

function SwarmAuthority:getInfo()
    return SwarmIdentity.getInfo(self.identity, self.registry)
end

function SwarmAuthority:reservePairingCredentials(computerId, computerLabel)
    return PairingSession.reserve(self, computerId, computerLabel)
end

function SwarmAuthority:commitPairingCredentials(computerId, computerLabel)
    return PairingSession.commit(self, computerId, computerLabel)
end

function SwarmAuthority:cancelPairingCredentials(computerId)
    return PairingSession.cancel(self, computerId)
end

function SwarmAuthority:issueCredentials(computerId, computerLabel)
    return PairingSession.issue(self, computerId, computerLabel)
end

function SwarmAuthority:getComputerSecret(computerId)
    return self.registry:getSecret(computerId)
end

function SwarmAuthority:getSecretLookup()
    return function(senderId)
        local computerSecret = self.registry:getSecret(senderId)
        if computerSecret then
            return computerSecret
        end
        return nil
    end
end

function SwarmAuthority:isAuthorized(computerId)
    return self.registry:isAuthorized(computerId)
end

function SwarmAuthority:getComputer(computerId)
    return self.registry:get(computerId)
end

function SwarmAuthority:getComputers()
    return self.registry:getActiveComputers()
end

function SwarmAuthority:revokeComputer(computerId)
    local ok = self.registry:revoke(computerId)
    if ok then
        self:save()
    end
    return ok
end

function SwarmAuthority:removeComputer(computerId)
    self.pendingPairings[computerId] = nil
    self.registry:remove(computerId)
    self:save()
end

function SwarmAuthority:deleteSwarm()
    self.pendingPairings = {}
    self.registry:delete()
    SwarmIdentity.delete(IDENTITY_PATH)
    self.identity = nil
    self.initialized = false
end

function SwarmAuthority:wrapMessage(data)
    if not self.initialized then
        error("Swarm not initialized")
    end
    return Envelope.wrap(data, self.identity.id, self.identity.secret)
end

function SwarmAuthority:unwrapMessage(envelope)
    if not self.initialized then
        return false, nil, nil, "Swarm not initialized"
    end
    return Envelope.unwrap(envelope, self:getSecretLookup())
end

return SwarmAuthority
