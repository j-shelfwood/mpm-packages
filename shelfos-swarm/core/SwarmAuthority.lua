-- SwarmAuthority.lua
-- Central authority for swarm management
-- The pocket computer acts as the "queen" - all zones must register with it
--
-- Responsibilities:
-- - Generate and store swarm identity
-- - Maintain zone registry
-- - Issue zone credentials during pairing
-- - Revoke compromised zones

local Registry = mpm('crypto/Registry')
local KeyPair = mpm('crypto/KeyPair')
local Envelope = mpm('crypto/Envelope')

local SwarmAuthority = {}
SwarmAuthority.__index = SwarmAuthority

-- Paths for swarm data
local REGISTRY_PATH = "/swarm_registry.dat"
local IDENTITY_PATH = "/swarm_identity.dat"

-- Create new swarm authority
function SwarmAuthority.new()
    local self = setmetatable({}, SwarmAuthority)
    self.registry = Registry.new(REGISTRY_PATH)
    self.identity = nil  -- { id, secret, fingerprint }
    self.initialized = false

    return self
end

-- Check if swarm exists
function SwarmAuthority:exists()
    return fs.exists(IDENTITY_PATH) and self.registry:exists()
end

-- Initialize the authority (load or create)
-- @return success, isNew
function SwarmAuthority:init()
    if self:exists() then
        return self:load()
    end
    return false, false  -- Not initialized, need to create
end

-- Create a new swarm
-- @param swarmName Human-readable name
-- @return success, swarmId
function SwarmAuthority:createSwarm(swarmName)
    -- Generate swarm identity
    local swarmId = "swarm_" .. os.getComputerID() .. "_" .. os.epoch("utc")
    local secret = self.registry:generateZoneSecret()
    local fingerprint = KeyPair.fingerprint(secret)

    self.identity = {
        id = swarmId,
        name = swarmName or ("Swarm " .. os.getComputerID()),
        secret = secret,
        fingerprint = fingerprint,
        createdAt = os.epoch("utc"),
        pocketId = os.getComputerID()
    }

    -- Initialize registry
    self.registry:initSwarm(swarmId, secret)

    -- Save
    local ok = self:save()
    if not ok then
        return false, nil
    end

    self.initialized = true
    return true, swarmId
end

-- Load existing swarm
-- @return success, isNew
function SwarmAuthority:load()
    -- Load identity
    if not fs.exists(IDENTITY_PATH) then
        return false, false
    end

    local file = fs.open(IDENTITY_PATH, "r")
    if not file then
        return false, false
    end

    local content = file.readAll()
    file.close()

    local ok, identity = pcall(textutils.unserialize, content)
    if not ok or not identity then
        return false, false
    end

    self.identity = identity

    -- Load registry
    local regOk = self.registry:load()
    if not regOk then
        return false, false
    end

    self.initialized = true
    return true, false
end

-- Save swarm state
-- @return success
function SwarmAuthority:save()
    -- Save identity
    local file = fs.open(IDENTITY_PATH, "w")
    if not file then
        return false
    end
    file.write(textutils.serialize(self.identity))
    file.close()

    -- Save registry
    return self.registry:save()
end

-- Get swarm info
function SwarmAuthority:getInfo()
    if not self.identity then
        return nil
    end
    return {
        id = self.identity.id,
        name = self.identity.name,
        fingerprint = self.identity.fingerprint,
        pocketId = self.identity.pocketId,
        zoneCount = self.registry:countActive()
    }
end

-- Generate credentials for a new zone
-- Called during pairing when zone is verified
-- @param zoneId Zone identifier
-- @param zoneLabel Human-readable label
-- @return credentials table { zoneSecret, swarmId, swarmFingerprint }
function SwarmAuthority:issueCredentials(zoneId, zoneLabel)
    if not self.initialized then
        return nil, "Swarm not initialized"
    end

    -- Generate unique secret for this zone
    local zoneSecret = self.registry:generateZoneSecret()

    -- Add to registry
    local entry, err = self.registry:add(zoneId, zoneLabel, zoneSecret)
    if not entry then
        return nil, err
    end

    -- Save registry
    self:save()

    -- Return credentials for zone
    return {
        zoneId = zoneId,
        zoneSecret = zoneSecret,
        swarmId = self.identity.id,
        swarmSecret = self.identity.secret,  -- Zone needs this to verify pocket messages
        swarmFingerprint = self.identity.fingerprint
    }
end

-- Get secret for a zone (for message verification)
-- @param zoneId Zone identifier
-- @return secret or nil
function SwarmAuthority:getZoneSecret(zoneId)
    return self.registry:getSecret(zoneId)
end

-- Create lookup function for Envelope.unwrap
-- @return function(senderId) -> secret
function SwarmAuthority:getSecretLookup()
    return function(senderId)
        -- Check if it's a zone
        local zoneSecret = self.registry:getSecret(senderId)
        if zoneSecret then
            return zoneSecret
        end
        -- Unknown sender
        return nil
    end
end

-- Check if zone is authorized
-- @param zoneId Zone identifier
-- @return boolean
function SwarmAuthority:isAuthorized(zoneId)
    return self.registry:isAuthorized(zoneId)
end

-- Get zone info
-- @param zoneId Zone identifier
-- @return entry or nil
function SwarmAuthority:getZone(zoneId)
    return self.registry:get(zoneId)
end

-- Get all active zones
-- @return array of zone entries
function SwarmAuthority:getZones()
    return self.registry:getActiveZones()
end

-- Revoke a zone
-- @param zoneId Zone identifier
-- @return success
function SwarmAuthority:revokeZone(zoneId)
    local ok = self.registry:revoke(zoneId)
    if ok then
        self:save()
    end
    return ok
end

-- Remove a zone completely
-- @param zoneId Zone identifier
function SwarmAuthority:removeZone(zoneId)
    self.registry:remove(zoneId)
    self:save()
end

-- Delete the entire swarm
function SwarmAuthority:deleteSwarm()
    self.registry:delete()
    if fs.exists(IDENTITY_PATH) then
        fs.delete(IDENTITY_PATH)
    end
    self.identity = nil
    self.initialized = false
end

-- Wrap a message for broadcast to all zones
-- @param data Message data
-- @return envelope
function SwarmAuthority:wrapMessage(data)
    if not self.initialized then
        error("Swarm not initialized")
    end
    return Envelope.wrap(data, self.identity.id, self.identity.secret)
end

-- Unwrap a message from a zone
-- @param envelope Received envelope
-- @return success, data, senderId, error
function SwarmAuthority:unwrapMessage(envelope)
    if not self.initialized then
        return false, nil, nil, "Swarm not initialized"
    end
    return Envelope.unwrap(envelope, self:getSecretLookup())
end

return SwarmAuthority
