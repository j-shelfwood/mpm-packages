-- Crypto.lua
-- Message signing and verification for secure rednet communication
-- Uses HMAC-like signing with shared secret

local Crypto = {}

-- Module state - use _G for truly global state that survives module reloading
-- This ensures Crypto.setSecret() in one module is visible to all others
-- even if mpm() doesn't cache modules properly
_G._shelfos_crypto = _G._shelfos_crypto or {
    secret = nil,
    nonces = {},
    rngSeeded = false
}
local _state = _G._shelfos_crypto
local NONCE_EXPIRY = 120000  -- 2 minutes in milliseconds
local MAX_MESSAGE_AGE = 60000  -- 1 minute in milliseconds

-- Seed RNG once per session with unique values
-- Prevents duplicate nonces across restarts
if not _state.rngSeeded then
    local seed = os.epoch("utc") + (os.getComputerID() * 100000) + math.floor(os.clock() * 1000)
    math.randomseed(seed)
    -- Burn initial values to improve randomness
    for _ = 1, 10 do math.random() end
    _state.rngSeeded = true
end

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
    _state.secret = secret
end

-- Check if secret is configured
function Crypto.hasSecret()
    return _state.secret ~= nil
end

-- Get current secret (for debugging)
function Crypto.getSecret()
    return _state.secret
end

-- Generate a random nonce
-- Format: computerID_timestamp_random to ensure uniqueness across computers and time
local function generateNonce()
    return string.format("%d_%d_%08x", os.getComputerID(), os.epoch("utc"), math.random(0, 0xFFFFFFFF))
end

-- Clean expired nonces
local function cleanNonces()
    local now = os.epoch("utc")
    for nonce, timestamp in pairs(_state.nonces) do
        if now - timestamp > NONCE_EXPIRY then
            _state.nonces[nonce] = nil
        end
    end
end

-- Sign a message with a specific key (internal)
-- @param data Table to sign
-- @param key Secret key to use for signing
-- @return Signed message envelope
local function signWithKey(data, key)
    local payload = textutils.serialize(data)
    local timestamp = os.epoch("utc")
    local nonce = generateNonce()

    -- Create signature from payload + timestamp + nonce + key
    local signatureBase = payload .. tostring(timestamp) .. nonce .. key
    local signature = hash(signatureBase)

    return {
        v = 1,  -- Protocol version
        p = payload,
        t = timestamp,
        n = nonce,
        s = signature
    }
end

-- Sign a message using the global secret
-- @param data Table to sign
-- @return Signed message envelope
function Crypto.sign(data)
    if not _state.secret then
        error("Crypto secret not configured. Call Crypto.setSecret() first.")
    end
    return signWithKey(data, _state.secret)
end

-- Sign a message with an ephemeral key (for pairing handshakes)
-- @param data Table to sign
-- @param key Ephemeral key (e.g., pairing code)
-- @return Signed message envelope
function Crypto.signWith(data, key)
    if type(key) ~= "string" or #key < 4 then
        error("Ephemeral key must be a string of at least 4 characters")
    end
    return signWithKey(data, key)
end

-- Verify a signed message with a specific key (internal)
-- @param envelope The signed message envelope
-- @param key Secret key to verify against
-- @param skipNonceCheck If true, don't check/record nonce (for stateless verification)
-- @return success (boolean), data (table or nil), error (string or nil)
local function verifyWithKey(envelope, key, skipNonceCheck)
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
    if not skipNonceCheck then
        cleanNonces()
        if _state.nonces[envelope.n] then
            return false, nil, "Duplicate nonce (replay attack)"
        end
    end

    -- Verify signature
    local signatureBase = envelope.p .. tostring(envelope.t) .. envelope.n .. key
    local expectedSignature = hash(signatureBase)

    if envelope.s ~= expectedSignature then
        return false, nil, "Invalid signature"
    end

    -- Record nonce (only for global secret verification)
    if not skipNonceCheck then
        _state.nonces[envelope.n] = envelope.t
    end

    -- Deserialize payload
    local ok, data = pcall(textutils.unserialize, envelope.p)
    if not ok then
        return false, nil, "Failed to deserialize payload"
    end

    return true, data, nil
end

-- Verify a signed message using the global secret
-- @param envelope The signed message envelope
-- @return success (boolean), data (table or nil), error (string or nil)
function Crypto.verify(envelope)
    if not _state.secret then
        return false, nil, "Crypto secret not configured"
    end
    return verifyWithKey(envelope, _state.secret, false)
end

-- Verify a signed message with an ephemeral key (for pairing handshakes)
-- @param envelope The signed message envelope
-- @param key Ephemeral key (e.g., pairing code)
-- @return success (boolean), data (table or nil), error (string or nil)
function Crypto.verifyWith(envelope, key)
    if type(key) ~= "string" or #key < 4 then
        return false, nil, "Ephemeral key must be a string of at least 4 characters"
    end
    -- Skip nonce check for ephemeral verification (pairing is one-time)
    return verifyWithKey(envelope, key, true)
end

-- Wrap and sign a message for sending (using global secret)
-- @param data The data to send
-- @return Signed envelope ready for rednet
function Crypto.wrap(data)
    return Crypto.sign(data)
end

-- Wrap and sign a message with an ephemeral key
-- @param data The data to send
-- @param key Ephemeral key (e.g., pairing code)
-- @return Signed envelope ready for rednet
function Crypto.wrapWith(data, key)
    return Crypto.signWith(data, key)
end

-- Unwrap and verify a received message (using global secret)
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

-- Unwrap and verify a received message with an ephemeral key
-- @param envelope The received envelope
-- @param key Ephemeral key (e.g., pairing code)
-- @return data (table or nil), error (string or nil)
function Crypto.unwrapWith(envelope, key)
    local ok, data, err = Crypto.verifyWith(envelope, key)
    if ok then
        return data, nil
    else
        return nil, err
    end
end

-- Generate a random secret (for initial setup)
-- @return A random 32-character secret
function Crypto.generateSecret()
    -- Seed RNG with unique values to prevent identical secrets on different computers
    -- Combine: epoch time + computer ID + a memory address approximation
    local seed = os.epoch("utc") + (os.getComputerID() * 100000)
    math.randomseed(seed)
    -- Burn a few values to improve randomness after seeding
    for _ = 1, 10 do math.random() end

    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local secret = ""
    for i = 1, 32 do
        local idx = math.random(1, #chars)
        secret = secret .. chars:sub(idx, idx)
    end
    return secret
end

return Crypto
