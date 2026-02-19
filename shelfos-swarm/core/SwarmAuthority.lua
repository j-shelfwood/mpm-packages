-- SwarmAuthority.lua
-- Central authority for swarm management
-- The pocket computer acts as the "queen" - all computers must register with it
--
-- Responsibilities:
-- - Generate and store swarm identity
-- - Maintain computer registry
-- - Issue computer credentials during pairing
-- - Revoke compromised computers

local Registry = mpm('crypto/Registry')
local KeyPair = mpm('crypto/KeyPair')
local Envelope = mpm('crypto/Envelope')

local SwarmAuthority = {}
SwarmAuthority.__index = SwarmAuthority

-- Paths for swarm data
local REGISTRY_PATH = "/swarm_registry.dat"
local IDENTITY_PATH = "/swarm_identity.dat"

local function copyEntry(entry)
    if type(entry) ~= "table" then
        return nil
    end

    local out = {}
    for k, v in pairs(entry) do
        out[k] = v
    end
    return out
end

-- Create new swarm authority
function SwarmAuthority.new()
    local self = setmetatable({}, SwarmAuthority)
    self.registry = Registry.new(REGISTRY_PATH)
    self.identity = nil  -- { id, secret, fingerprint }
    self.initialized = false
    self.pendingPairings = {}

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
    local secret = self.registry:generateSecret()
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
        computerCount = self.registry:countActive()
    }
end

-- Prepare credentials for a computer without mutating persistent registry.
-- Caller must finalize via commitPairingCredentials() on successful handshake
-- or cancelPairingCredentials() on failure.
-- @param computerId Computer identifier
-- @param computerLabel Human-readable label
-- @return credentials table
function SwarmAuthority:reservePairingCredentials(computerId, computerLabel)
    if not self.initialized then
        return nil, "Swarm not initialized"
    end
    if not computerId then
        return nil, "Missing computer ID"
    end

    local existing = self.registry:get(computerId)
    local previous = copyEntry(existing)
    local computerSecret = existing and existing.secret or nil
    if not computerSecret or (existing and existing.status ~= "active") then
        computerSecret = self.registry:generateSecret()
    end

    local creds = {
        computerId = computerId,
        computerSecret = computerSecret,
        swarmId = self.identity.id,
        swarmSecret = self.identity.secret,  -- Computer needs this to verify pocket messages
        swarmFingerprint = self.identity.fingerprint
    }

    self.pendingPairings[computerId] = {
        computerId = computerId,
        computerLabel = computerLabel,
        previous = previous,
        creds = creds
    }

    return creds
end

-- Commit a previously reserved credential issuance after successful handshake.
-- @param computerId Computer identifier
-- @param computerLabel Optional latest human-readable label
-- @return committed credentials table
function SwarmAuthority:commitPairingCredentials(computerId, computerLabel)
    if not self.initialized then
        return nil, "Swarm not initialized"
    end

    local pending = self.pendingPairings[computerId]
    if not pending then
        return nil, "No pending pairing"
    end

    local entry, err = self.registry:upsert(
        computerId,
        computerLabel or pending.computerLabel,
        pending.creds.computerSecret
    )
    if not entry then
        return nil, err
    end

    self.pendingPairings[computerId] = nil
    self:save()

    return {
        computerId = computerId,
        computerSecret = entry.secret,
        swarmId = self.identity.id,
        swarmSecret = self.identity.secret,
        swarmFingerprint = self.identity.fingerprint
    }
end

-- Roll back a pending pairing reservation.
-- @param computerId Computer identifier
-- @return true if rollback was applied (or no pending reservation)
function SwarmAuthority:cancelPairingCredentials(computerId)
    local pending = self.pendingPairings[computerId]
    if not pending then
        return true
    end

    if pending.previous then
        self.registry.entries[computerId] = pending.previous
    else
        self.registry:remove(computerId)
    end

    self.pendingPairings[computerId] = nil
    self:save()
    return true
end

-- Backward-compatible single-step issuance used by legacy call sites/tests.
function SwarmAuthority:issueCredentials(computerId, computerLabel)
    local creds, err = self:reservePairingCredentials(computerId, computerLabel)
    if not creds then
        return nil, err
    end

    local committed, commitErr = self:commitPairingCredentials(computerId, computerLabel)
    if not committed then
        return nil, commitErr
    end

    return committed
end

-- Get secret for a computer (for message verification)
-- @param computerId Computer identifier
-- @return secret or nil
function SwarmAuthority:getComputerSecret(computerId)
    return self.registry:getSecret(computerId)
end

-- Create lookup function for Envelope.unwrap
-- @return function(senderId) -> secret
function SwarmAuthority:getSecretLookup()
    return function(senderId)
        -- Check if it's a computer
        local computerSecret = self.registry:getSecret(senderId)
        if computerSecret then
            return computerSecret
        end
        -- Unknown sender
        return nil
    end
end

-- Check if computer is authorized
-- @param computerId Computer identifier
-- @return boolean
function SwarmAuthority:isAuthorized(computerId)
    return self.registry:isAuthorized(computerId)
end

-- Get computer info
-- @param computerId Computer identifier
-- @return entry or nil
function SwarmAuthority:getComputer(computerId)
    return self.registry:get(computerId)
end

-- Get all active computers
-- @return array of computer entries
function SwarmAuthority:getComputers()
    return self.registry:getActiveComputers()
end

-- Revoke a computer
-- @param computerId Computer identifier
-- @return success
function SwarmAuthority:revokeComputer(computerId)
    local ok = self.registry:revoke(computerId)
    if ok then
        self:save()
    end
    return ok
end

-- Remove a computer completely
-- @param computerId Computer identifier
function SwarmAuthority:removeComputer(computerId)
    self.pendingPairings[computerId] = nil
    self.registry:remove(computerId)
    self:save()
end

-- Delete the entire swarm
function SwarmAuthority:deleteSwarm()
    self.pendingPairings = {}
    self.registry:delete()
    if fs.exists(IDENTITY_PATH) then
        fs.delete(IDENTITY_PATH)
    end
    self.identity = nil
    self.initialized = false
end

-- Wrap a message for broadcast to all computers
-- @param data Message data
-- @return envelope
function SwarmAuthority:wrapMessage(data)
    if not self.initialized then
        error("Swarm not initialized")
    end
    return Envelope.wrap(data, self.identity.id, self.identity.secret)
end

-- Unwrap a message from a computer
-- @param envelope Received envelope
-- @return success, data, senderId, error
function SwarmAuthority:unwrapMessage(envelope)
    if not self.initialized then
        return false, nil, nil, "Swarm not initialized"
    end
    return Envelope.unwrap(envelope, self:getSecretLookup())
end

return SwarmAuthority
