local Registry = mpm('crypto/Registry')

local SwarmRegistry = {}
SwarmRegistry.__index = SwarmRegistry

function SwarmRegistry.new(registryPath)
    local self = setmetatable({}, SwarmRegistry)
    self.backend = Registry.new(registryPath)
    return self
end

function SwarmRegistry:exists()
    return self.backend:exists()
end

function SwarmRegistry:load()
    return self.backend:load()
end

function SwarmRegistry:save()
    return self.backend:save()
end

function SwarmRegistry:initSwarm(swarmId, secret)
    self.backend:initSwarm(swarmId, secret)
end

function SwarmRegistry:generateSecret()
    return self.backend:generateSecret()
end

function SwarmRegistry:upsert(computerId, computerLabel, computerSecret)
    return self.backend:upsert(computerId, computerLabel, computerSecret)
end

function SwarmRegistry:get(computerId)
    return self.backend:get(computerId)
end

function SwarmRegistry:set(computerId, entry)
    self.backend.entries[computerId] = entry
end

function SwarmRegistry:getSecret(computerId)
    return self.backend:getSecret(computerId)
end

function SwarmRegistry:isAuthorized(computerId)
    return self.backend:isAuthorized(computerId)
end

function SwarmRegistry:getActiveComputers()
    return self.backend:getActiveComputers()
end

function SwarmRegistry:countActive()
    return self.backend:countActive()
end

function SwarmRegistry:revoke(computerId)
    return self.backend:revoke(computerId)
end

function SwarmRegistry:remove(computerId)
    self.backend:remove(computerId)
end

function SwarmRegistry:delete()
    self.backend:delete()
end

return SwarmRegistry
