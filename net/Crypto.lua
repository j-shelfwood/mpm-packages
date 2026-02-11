-- Crypto.lua
-- Message signing and verification for secure rednet communication
-- Uses HMAC-like signing with shared secret

local Crypto = {}

-- Module state
local _secret = nil
local _nonces = {}  -- Track recent nonces to prevent replay
local NONCE_EXPIRY = 120000  -- 2 minutes in milliseconds
local MAX_MESSAGE_AGE = 60000  -- 1 minute in milliseconds

-- Simple hash function (not cryptographically secure, but sufficient for CC)
-- In a real environment, you'd want a proper hash
local function simpleHash(str)
    local h = 5381
    for i = 1, #str do
        h = ((h * 33) + string.byte(str, i)) % 4294967296
    end
    return string.format("%08x", h)
end

-- Generate a more robust hash by multiple passes
local function hash(str)
    local h1 = simpleHash(str)
    local h2 = simpleHash(str .. h1)
    local h3 = simpleHash(h1 .. str .. h2)
    return h1 .. h2 .. h3
end

-- Set the shared secret (call once at startup)
-- @param secret The shared secret string
function Crypto.setSecret(secret)
    if type(secret) ~= "string" or #secret < 16 then
        error("Secret must be a string of at least 16 characters")
    end
    _secret = secret
end

-- Check if secret is configured
function Crypto.hasSecret()
    return _secret ~= nil
end

-- Generate a random nonce
local function generateNonce()
    return string.format("%08x%08x", math.random(0, 0xFFFFFFFF), os.epoch("utc"))
end

-- Clean expired nonces
local function cleanNonces()
    local now = os.epoch("utc")
    for nonce, timestamp in pairs(_nonces) do
        if now - timestamp > NONCE_EXPIRY then
            _nonces[nonce] = nil
        end
    end
end

-- Sign a message
-- @param data Table to sign
-- @return Signed message envelope
function Crypto.sign(data)
    if not _secret then
        error("Crypto secret not configured. Call Crypto.setSecret() first.")
    end

    local payload = textutils.serialize(data)
    local timestamp = os.epoch("utc")
    local nonce = generateNonce()

    -- Create signature from payload + timestamp + nonce + secret
    local signatureBase = payload .. tostring(timestamp) .. nonce .. _secret
    local signature = hash(signatureBase)

    return {
        v = 1,  -- Protocol version
        p = payload,
        t = timestamp,
        n = nonce,
        s = signature
    }
end

-- Verify a signed message
-- @param envelope The signed message envelope
-- @return success (boolean), data (table or nil), error (string or nil)
function Crypto.verify(envelope)
    if not _secret then
        return false, nil, "Crypto secret not configured"
    end

    -- Check envelope structure
    if type(envelope) ~= "table" then
        return false, nil, "Invalid envelope: not a table"
    end

    if not envelope.p or not envelope.t or not envelope.n or not envelope.s then
        return false, nil, "Invalid envelope: missing fields"
    end

    -- Check timestamp (prevent replay of old messages)
    local now = os.epoch("utc")
    local age = now - envelope.t

    if age > MAX_MESSAGE_AGE then
        return false, nil, "Message expired"
    end

    if age < -5000 then  -- 5 second tolerance for clock skew
        return false, nil, "Message from future"
    end

    -- Check nonce (prevent replay within time window)
    cleanNonces()
    if _nonces[envelope.n] then
        return false, nil, "Duplicate nonce (replay attack)"
    end

    -- Verify signature
    local signatureBase = envelope.p .. tostring(envelope.t) .. envelope.n .. _secret
    local expectedSignature = hash(signatureBase)

    if envelope.s ~= expectedSignature then
        return false, nil, "Invalid signature"
    end

    -- Record nonce
    _nonces[envelope.n] = envelope.t

    -- Deserialize payload
    local ok, data = pcall(textutils.unserialize, envelope.p)
    if not ok then
        return false, nil, "Failed to deserialize payload"
    end

    return true, data, nil
end

-- Wrap and sign a message for sending
-- @param data The data to send
-- @return Signed envelope ready for rednet
function Crypto.wrap(data)
    return Crypto.sign(data)
end

-- Unwrap and verify a received message
-- @param envelope The received envelope
-- @return data (table or nil), error (string or nil)
function Crypto.unwrap(envelope)
    local ok, data, err = Crypto.verify(envelope)
    if ok then
        return data, nil
    else
        return nil, err
    end
end

-- Generate a random secret (for initial setup)
-- @return A random 32-character secret
function Crypto.generateSecret()
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local secret = ""
    for i = 1, 32 do
        local idx = math.random(1, #chars)
        secret = secret .. chars:sub(idx, idx)
    end
    return secret
end

return Crypto
