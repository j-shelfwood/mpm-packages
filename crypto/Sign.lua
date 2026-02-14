-- Sign.lua
-- Message signing with private key
-- Creates HMAC-like signatures that can be verified by anyone with the public key
-- (In practice, verification requires the signature + message + public key)

local Sign = {}

-- Simple hash function
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

-- Strong hash
local function strongHash(str)
    local h1 = hash(str)
    local h2 = hash(str .. h1)
    local h3 = hash(h1 .. str .. h2)
    local h4 = hash(h2 .. h3 .. str)
    return h1 .. h2 .. h3 .. h4
end

-- Generate nonce
local function generateNonce()
    return string.format("%d_%d_%08x",
        os.getComputerID(),
        os.epoch("utc"),
        math.random(0, 0xFFFFFFFF)
    )
end

-- Sign data with private key
-- @param data Table to sign
-- @param privateKey The signer's private key
-- @param publicKey The signer's public key (included in envelope for verification)
-- @return signed envelope
function Sign.sign(data, privateKey, publicKey)
    if type(privateKey) ~= "string" or #privateKey < 16 then
        error("CRYPTO: Invalid private key for signing")
    end
    if type(publicKey) ~= "string" or #publicKey < 16 then
        error("CRYPTO: Invalid public key for signing")
    end

    local payload = textutils.serialize(data)
    local timestamp = os.epoch("utc")
    local nonce = generateNonce()

    -- Signature = hash(payload + timestamp + nonce + privateKey)
    local signatureBase = payload .. tostring(timestamp) .. nonce .. privateKey
    local signature = strongHash(signatureBase)

    return {
        v = 2,  -- Protocol version (2 = PKI)
        p = payload,
        t = timestamp,
        n = nonce,
        s = signature,
        k = publicKey  -- Sender's public key for verification
    }
end

-- Create a signed message for a specific recipient
-- Includes recipient's public key to prevent relay attacks
-- @param data Table to sign
-- @param privateKey Signer's private key
-- @param publicKey Signer's public key
-- @param recipientPubKey Intended recipient's public key
-- @return signed envelope with recipient binding
function Sign.signFor(data, privateKey, publicKey, recipientPubKey)
    if type(recipientPubKey) ~= "string" or #recipientPubKey < 16 then
        error("CRYPTO: Invalid recipient public key")
    end

    local envelope = Sign.sign(data, privateKey, publicKey)
    envelope.r = recipientPubKey  -- Recipient binding

    -- Re-sign with recipient included
    local signatureBase = envelope.p .. tostring(envelope.t) .. envelope.n .. envelope.r .. privateKey
    envelope.s = strongHash(signatureBase)

    return envelope
end

-- Quick sign helper (for when you have a keypair table)
-- @param data Table to sign
-- @param keypair { private, public }
-- @return signed envelope
function Sign.withKeypair(data, keypair)
    if type(keypair) ~= "table" or not keypair.private or not keypair.public then
        error("CRYPTO: Invalid keypair")
    end
    return Sign.sign(data, keypair.private, keypair.public)
end

return Sign
