-- KeyPair.lua
-- Identity keypair generation and management
-- Uses identity-based crypto suitable for CC:Tweaked constraints
--
-- Model: Each device has a unique identity (keypair)
-- - privateKey: Random 32-byte secret (never shared)
-- - publicKey: Hash of private key (shared during pairing)
-- - Signing uses HMAC with private key
-- - Verification requires knowing the signer's public key + their signature

local KeyPair = {}

-- Simple hash function (djb2 extended)
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

-- More robust hash by multiple passes
local function strongHash(str)
    local h1 = hash(str)
    local h2 = hash(str .. h1)
    local h3 = hash(h1 .. str .. h2)
    local h4 = hash(h2 .. h3 .. str)
    return h1 .. h2 .. h3 .. h4  -- 64 chars
end

-- Generate random bytes
local function randomBytes(length)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local result = ""
    for i = 1, length do
        local idx = math.random(1, #chars)
        result = result .. chars:sub(idx, idx)
    end
    return result
end

-- Seed RNG with good entropy
local function ensureSeeded()
    if not _G._crypto_seeded then
        local seed = os.epoch("utc") +
                     (os.getComputerID() * 100000) +
                     math.floor(os.clock() * 10000)
        math.randomseed(seed)
        -- Burn initial values
        for _ = 1, 20 do math.random() end
        _G._crypto_seeded = true
    end
end

-- Generate a new keypair
-- @return { private = string, public = string }
function KeyPair.generate()
    ensureSeeded()

    local privateKey = randomBytes(32)
    local publicKey = strongHash(privateKey)

    return {
        private = privateKey,
        public = publicKey
    }
end

-- Derive public key from private key
-- @param privateKey The private key
-- @return public key string
function KeyPair.derivePublic(privateKey)
    if type(privateKey) ~= "string" or #privateKey < 16 then
        error("Invalid private key")
    end
    return strongHash(privateKey)
end

-- Generate fingerprint from public key (human-readable)
-- Format: XXXX-XXXX-XXXX (12 chars from hash)
-- @param publicKey The public key
-- @return fingerprint string
function KeyPair.fingerprint(publicKey)
    if type(publicKey) ~= "string" or #publicKey < 16 then
        error("Invalid public key")
    end

    local fp = hash(publicKey):upper():sub(1, 12)
    return fp:sub(1, 4) .. "-" .. fp:sub(5, 8) .. "-" .. fp:sub(9, 12)
end

-- Save keypair to file
-- @param path File path
-- @param keypair The keypair table
-- @return success
function KeyPair.save(path, keypair)
    if not keypair or not keypair.private or not keypair.public then
        return false, "Invalid keypair"
    end

    local file = fs.open(path, "w")
    if not file then
        return false, "Cannot open file"
    end

    file.write(textutils.serialize(keypair))
    file.close()
    return true
end

-- Load keypair from file
-- @param path File path
-- @return keypair or nil, error
function KeyPair.load(path)
    if not fs.exists(path) then
        return nil, "File not found"
    end

    local file = fs.open(path, "r")
    if not file then
        return nil, "Cannot open file"
    end

    local content = file.readAll()
    file.close()

    local ok, keypair = pcall(textutils.unserialize, content)
    if not ok or not keypair then
        return nil, "Invalid keypair file"
    end

    if not keypair.private or not keypair.public then
        return nil, "Incomplete keypair"
    end

    return keypair
end

-- Check if keypair exists at path
-- @param path File path
-- @return boolean
function KeyPair.exists(path)
    return fs.exists(path)
end

-- Delete keypair file
-- @param path File path
function KeyPair.delete(path)
    if fs.exists(path) then
        fs.delete(path)
    end
end

return KeyPair
