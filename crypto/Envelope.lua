-- Envelope.lua
-- Message envelope creation and verification
-- Wraps messages with signatures for secure transmission
--
-- This module provides the practical interface for signing/verifying messages
-- using the identity-based crypto system.

local KeyPair = mpm('crypto/KeyPair')

local Envelope = {}

-- Hash functions (consistent with other modules)
local function hash(str)
    local h1 = 5381
    local h2 = 52711
    for i = 1, #str do
        local b = string.byte(str, i)
        h1 = ((h1 * 33) + b) % 4294967296
        h2 = ((h2 * 33) + (b * 2)) % 4294967296
    end
    return string.format("%08x%08x", h1, h2)
end

local function strongHash(str)
    local h1 = hash(str)
    local h2 = hash(str .. h1)
    local h3 = hash(h1 .. str .. h2)
    local h4 = hash(h2 .. h3 .. str)
    return h1 .. h2 .. h3 .. h4
end

local function generateNonce()
    return string.format("%d_%d_%08x",
        os.getComputerID(),
        os.epoch("utc"),
        math.random(0, 0xFFFFFFFF)
    )
end

-- Nonce tracking
local _nonces = {}
local NONCE_EXPIRY = 120000
local MAX_AGE = 60000

local function cleanNonces()
    local now = os.epoch("utc")
    for nonce, ts in pairs(_nonces) do
        if now - ts > NONCE_EXPIRY then
            _nonces[nonce] = nil
        end
    end
end

-- Wrap a message with signature
-- @param data The data to send
-- @param senderId Sender's identity string
-- @param secret The shared secret for this communication pair
-- @return Signed envelope
function Envelope.wrap(data, senderId, secret)
    if type(secret) ~= "string" or #secret < 16 then
        error("CRYPTO: Invalid secret for wrapping")
    end

    local payload = textutils.serialize(data)
    local timestamp = os.epoch("utc")
    local nonce = generateNonce()

    -- Signature includes sender ID for authenticity
    local signatureBase = payload .. senderId .. tostring(timestamp) .. nonce .. secret
    local signature = strongHash(signatureBase)

    return {
        v = 2,
        p = payload,
        f = senderId,  -- from
        t = timestamp,
        n = nonce,
        s = signature
    }
end

-- Unwrap and verify a message
-- @param envelope The received envelope
-- @param getSecret Function(senderId) -> secret or nil
-- @return success, data, senderId, error
function Envelope.unwrap(envelope, getSecret)
    -- Validate structure
    if type(envelope) ~= "table" then
        return false, nil, nil, "Invalid envelope"
    end

    if envelope.v ~= 2 then
        return false, nil, nil, "Wrong protocol version"
    end

    if not envelope.p or not envelope.f or not envelope.t or not envelope.n or not envelope.s then
        return false, nil, nil, "Missing envelope fields"
    end

    local senderId = envelope.f

    -- Get secret for this sender
    local secret = getSecret(senderId)
    if not secret then
        return false, nil, senderId, "Unknown sender"
    end

    -- Check timestamp
    local now = os.epoch("utc")
    local age = now - envelope.t

    if age > MAX_AGE then
        return false, nil, senderId, "Message expired"
    end

    if age < -5000 then
        return false, nil, senderId, "Message from future"
    end

    -- Check nonce
    cleanNonces()
    if _nonces[envelope.n] then
        return false, nil, senderId, "Replay attack"
    end

    -- Verify signature
    local signatureBase = envelope.p .. senderId .. tostring(envelope.t) .. envelope.n .. secret
    local expectedSig = strongHash(signatureBase)

    if envelope.s ~= expectedSig then
        return false, nil, senderId, "Invalid signature"
    end

    -- Record nonce
    _nonces[envelope.n] = envelope.t

    -- Deserialize
    local ok, data = pcall(textutils.unserialize, envelope.p)
    if not ok then
        return false, nil, senderId, "Failed to deserialize"
    end

    return true, data, senderId, nil
end

-- Wrap for broadcast (signed but anyone with secret can verify)
-- @param data The data
-- @param senderId Sender ID
-- @param secret Shared swarm secret
-- @return Envelope
function Envelope.wrapBroadcast(data, senderId, secret)
    return Envelope.wrap(data, senderId, secret)
end

-- Clear nonce cache
function Envelope.clearNonces()
    _nonces = {}
end

return Envelope
