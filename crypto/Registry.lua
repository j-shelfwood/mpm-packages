-- Registry.lua
-- Trust registry for managing authorized identities
-- Used by SwarmAuthority to track which zones are authorized
--
-- Each entry contains:
-- - id: Unique zone identifier
-- - label: Human-readable name
-- - secret: Shared secret for this zone (generated during pairing)
-- - fingerprint: Human-readable fingerprint for verification
-- - addedAt: Timestamp when added
-- - status: "active", "revoked", "pending"

local KeyPair = mpm('crypto/KeyPair')

local Registry = {}
Registry.__index = Registry

-- Create new registry
-- @param path File path for persistence
function Registry.new(path)
    local self = setmetatable({}, Registry)
    self.path = path
    self.entries = {}
    self.swarmId = nil
    self.swarmSecret = nil

    return self
end

-- Initialize swarm identity
-- @param swarmId Unique swarm identifier
-- @param secret Swarm master secret
function Registry:initSwarm(swarmId, secret)
    self.swarmId = swarmId
    self.swarmSecret = secret
end

-- Generate a new zone secret
-- @return secret string
function Registry:generateZoneSecret()
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local secret = ""
    for i = 1, 32 do
        local idx = math.random(1, #chars)
        secret = secret .. chars:sub(idx, idx)
    end
    return secret
end

-- Add a new zone to registry
-- @param zoneId Zone identifier
-- @param label Human-readable label
-- @param secret Zone's secret (generated during pairing)
-- @return entry
function Registry:add(zoneId, label, secret)
    if self.entries[zoneId] then
        return nil, "Zone already exists"
    end

    local entry = {
        id = zoneId,
        label = label or ("Zone " .. zoneId),
        secret = secret,
        fingerprint = KeyPair.fingerprint(secret),
        addedAt = os.epoch("utc"),
        status = "active"
    }

    self.entries[zoneId] = entry
    return entry
end

-- Get zone entry
-- @param zoneId Zone identifier
-- @return entry or nil
function Registry:get(zoneId)
    return self.entries[zoneId]
end

-- Get zone secret (for message verification)
-- @param zoneId Zone identifier
-- @return secret or nil
function Registry:getSecret(zoneId)
    local entry = self.entries[zoneId]
    if entry and entry.status == "active" then
        return entry.secret
    end
    return nil
end

-- Check if zone is authorized
-- @param zoneId Zone identifier
-- @return boolean
function Registry:isAuthorized(zoneId)
    local entry = self.entries[zoneId]
    return entry ~= nil and entry.status == "active"
end

-- Revoke a zone
-- @param zoneId Zone identifier
-- @return success
function Registry:revoke(zoneId)
    local entry = self.entries[zoneId]
    if entry then
        entry.status = "revoked"
        entry.revokedAt = os.epoch("utc")
        return true
    end
    return false
end

-- Remove a zone completely
-- @param zoneId Zone identifier
function Registry:remove(zoneId)
    self.entries[zoneId] = nil
end

-- Get all active zones
-- @return array of entries
function Registry:getActiveZones()
    local result = {}
    for _, entry in pairs(self.entries) do
        if entry.status == "active" then
            table.insert(result, entry)
        end
    end
    return result
end

-- Get all zones (including revoked)
-- @return array of entries
function Registry:getAllZones()
    local result = {}
    for _, entry in pairs(self.entries) do
        table.insert(result, entry)
    end
    return result
end

-- Count active zones
-- @return number
function Registry:countActive()
    local count = 0
    for _, entry in pairs(self.entries) do
        if entry.status == "active" then
            count = count + 1
        end
    end
    return count
end

-- Save registry to disk
-- @return success
function Registry:save()
    if not self.path then
        return false, "No path configured"
    end

    local data = {
        version = 1,
        swarmId = self.swarmId,
        swarmSecret = self.swarmSecret,
        entries = self.entries
    }

    local file = fs.open(self.path, "w")
    if not file then
        return false, "Cannot open file"
    end

    file.write(textutils.serialize(data))
    file.close()
    return true
end

-- Load registry from disk
-- @return success
function Registry:load()
    if not self.path or not fs.exists(self.path) then
        return false, "File not found"
    end

    local file = fs.open(self.path, "r")
    if not file then
        return false, "Cannot open file"
    end

    local content = file.readAll()
    file.close()

    local ok, data = pcall(textutils.unserialize, content)
    if not ok or not data then
        return false, "Invalid registry file"
    end

    self.swarmId = data.swarmId
    self.swarmSecret = data.swarmSecret
    self.entries = data.entries or {}

    return true
end

-- Check if registry exists on disk
function Registry:exists()
    return self.path and fs.exists(self.path)
end

-- Delete registry from disk
function Registry:delete()
    if self.path and fs.exists(self.path) then
        fs.delete(self.path)
    end
    self.entries = {}
    self.swarmId = nil
    self.swarmSecret = nil
end

return Registry
