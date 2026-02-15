-- Registry.lua
-- Trust registry for managing authorized identities
-- Used by SwarmAuthority to track which computers are authorized
--
-- Each entry contains:
-- - id: Unique computer identifier
-- - label: Human-readable name
-- - secret: Shared secret for this computer (generated during pairing)
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

-- Generate a new secret for a computer
-- @return secret string
function Registry:generateSecret()
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local secret = ""
    for i = 1, 32 do
        local idx = math.random(1, #chars)
        secret = secret .. chars:sub(idx, idx)
    end
    return secret
end

-- Add a new computer to registry
-- @param computerId Computer identifier
-- @param label Human-readable label
-- @param secret Computer's secret (generated during pairing)
-- @return entry
function Registry:add(computerId, label, secret)
    if self.entries[computerId] then
        return nil, "Computer already exists"
    end

    local entry = {
        id = computerId,
        label = label or ("Computer " .. computerId),
        secret = secret,
        fingerprint = KeyPair.fingerprint(secret),
        addedAt = os.epoch("utc"),
        status = "active"
    }

    self.entries[computerId] = entry
    return entry
end

-- Add or update a computer entry (re-pair support)
-- @param computerId Computer identifier
-- @param label Human-readable label
-- @param secret Optional new secret
-- @return entry
function Registry:upsert(computerId, label, secret)
    local entry = self.entries[computerId]
    if entry then
        if label then
            entry.label = label
        end
        if secret then
            entry.secret = secret
            entry.fingerprint = KeyPair.fingerprint(secret)
        end
        entry.status = "active"
        entry.addedAt = os.epoch("utc")
        return entry
    end

    return self:add(computerId, label, secret)
end

-- Get computer entry
-- @param computerId Computer identifier
-- @return entry or nil
function Registry:get(computerId)
    return self.entries[computerId]
end

-- Get computer secret (for message verification)
-- @param computerId Computer identifier
-- @return secret or nil
function Registry:getSecret(computerId)
    local entry = self.entries[computerId]
    if entry and entry.status == "active" then
        return entry.secret
    end
    return nil
end

-- Check if computer is authorized
-- @param computerId Computer identifier
-- @return boolean
function Registry:isAuthorized(computerId)
    local entry = self.entries[computerId]
    return entry ~= nil and entry.status == "active"
end

-- Revoke a computer
-- @param computerId Computer identifier
-- @return success
function Registry:revoke(computerId)
    local entry = self.entries[computerId]
    if entry then
        entry.status = "revoked"
        entry.revokedAt = os.epoch("utc")
        return true
    end
    return false
end

-- Remove a computer completely
-- @param computerId Computer identifier
function Registry:remove(computerId)
    self.entries[computerId] = nil
end

-- Get all active computers
-- @return array of entries
function Registry:getActiveComputers()
    local result = {}
    for _, entry in pairs(self.entries) do
        if entry.status == "active" then
            table.insert(result, entry)
        end
    end
    return result
end

-- Get all computers (including revoked)
-- @return array of entries
function Registry:getAllComputers()
    local result = {}
    for _, entry in pairs(self.entries) do
        table.insert(result, entry)
    end
    return result
end

-- Count active computers
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
