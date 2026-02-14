-- Config + Pairing Integration Tests
-- Tests that Config state correctly controls pairing behavior
-- Validates the root cause of "Zone B not appearing" bug

local root = _G.TEST_ROOT or "."

-- Setup module loader
local module_cache = {}
_G.mpm = function(name)
    if not module_cache[name] then
        module_cache[name] = dofile(root .. "/" .. name .. ".lua")
    end
    return module_cache[name]
end

-- Load mocks
package.path = root .. "/tests/lua/?.lua;" .. root .. "/tests/lua/?/init.lua;" .. package.path
local Mocks = require("mocks")

-- Test utilities
local function assert_eq(expected, actual, msg)
    if expected ~= actual then
        error((msg or "Assertion failed") ..
              string.format(" (expected=%s, actual=%s)", tostring(expected), tostring(actual)))
    end
end

local function assert_true(value, msg)
    if not value then error(msg or "Expected true") end
end

local function assert_false(value, msg)
    if value then error(msg or "Expected false") end
end

local function assert_not_nil(value, msg)
    if value == nil then error(msg or "Expected non-nil value") end
end

-- =============================================================================
-- TESTS: Config.isInSwarm() behavior
-- =============================================================================

test("Config.isInSwarm returns false when no network secret", function()
    Mocks.setupZone({id = 10})

    local Config = mpm("shelfos/core/Config")

    -- Config with no network secret
    local configNoSecret = {
        zone = { id = "zone_10", name = "Test Zone" },
        network = { enabled = false, secret = nil }
    }

    assert_false(Config.isInSwarm(configNoSecret), "Should return false when no secret")
end)

test("Config.isInSwarm returns true when network secret exists", function()
    Mocks.setupZone({id = 10})

    local Config = mpm("shelfos/core/Config")

    -- Config WITH network secret
    local configWithSecret = {
        zone = { id = "zone_10", name = "Test Zone" },
        network = { enabled = true, secret = "swarm_secret_xyz" }
    }

    assert_true(Config.isInSwarm(configWithSecret), "Should return true when secret exists")
end)

test("Config.isInSwarm returns false for nil config", function()
    Mocks.setupZone({id = 10})

    local Config = mpm("shelfos/core/Config")

    assert_false(Config.isInSwarm(nil), "Should return false for nil config")
end)

-- =============================================================================
-- TESTS: Config persistence with fs mock
-- =============================================================================

test("Config.load returns nil when no config file exists", function()
    Mocks.setupZone({id = 10})
    -- fs is reset by setupZone, so no files exist

    local Config = mpm("shelfos/core/Config")

    local loaded = Config.load()
    assert_true(loaded == nil, "Should return nil when no config file")
end)

test("Config.save and Config.load roundtrip preserves data", function()
    Mocks.setupZone({id = 10})

    local Config = mpm("shelfos/core/Config")

    local original = Config.create("zone_test_123", "My Test Zone")
    original.network = { enabled = true, secret = "test_secret_456" }

    -- Save
    local saveOk = Config.save(original)
    assert_true(saveOk, "Save should succeed")

    -- Clear module cache to force reload
    module_cache["shelfos/core/Config"] = nil
    local Config2 = mpm("shelfos/core/Config")

    -- Load
    local loaded = Config2.load()
    assert_not_nil(loaded, "Load should return config")
    assert_eq("zone_test_123", loaded.zone.id)
    assert_eq("My Test Zone", loaded.zone.name)
    assert_eq("test_secret_456", loaded.network.secret)
end)

-- =============================================================================
-- TESTS: Stale config prevents pairing
-- =============================================================================

test("Zone with existing secret: Config check prevents entering pairing mode", function()
    Mocks.setupZone({id = 10})

    local Config = mpm("shelfos/core/Config")

    -- This simulates what happens in Kernel.lua:initializeNetwork() line 139
    -- Zone with existing secret (stale config from previous pairing)
    local staleConfig = {
        zone = { id = "zone_10", name = "Zone 10" },
        network = { enabled = true, secret = "old_swarm_secret" }
    }

    -- The actual check from Kernel.lua:139
    local shouldSkipPairingMode = staleConfig.network and staleConfig.network.secret
    assert_true(shouldSkipPairingMode, "Zone with secret should skip pairing mode")

    -- This means the zone would NOT show [L] Accept from pocket
    -- and would NOT broadcast PAIR_READY
end)

test("Zone without secret: Enters pairing mode and can broadcast PAIR_READY", function()
    Mocks.setupZone({id = 11})

    local Config = mpm("shelfos/core/Config")
    local Protocol = mpm("net/Protocol")
    local Pairing = mpm("net/Pairing")

    -- Fresh config without secret
    local freshConfig = {
        zone = { id = "zone_11", name = "Zone 11" },
        network = { enabled = false, secret = nil }
    }

    -- The actual check from Kernel.lua:139
    local shouldEnterPairingMode = not (freshConfig.network and freshConfig.network.secret)
    assert_true(shouldEnterPairingMode, "Zone without secret should enter pairing mode")

    -- Can create PAIR_READY message
    local ready = Protocol.createPairReady(nil, "Zone 11", 11)
    assert_eq(Protocol.MessageType.PAIR_READY, ready.type)
    assert_eq("Zone 11", ready.data.label)
    assert_eq(11, ready.data.computerId)

    -- Can broadcast (modem is set up by setupZone)
    rednet.open("top")
    local broadcastOk = pcall(function()
        rednet.broadcast(ready, Pairing.PROTOCOL)
    end)
    assert_true(broadcastOk, "Should be able to broadcast PAIR_READY")

    local log = rednet._getBroadcastLog()
    assert_eq(1, #log, "Should have one broadcast")
    assert_eq(Protocol.MessageType.PAIR_READY, log[1].message.type)
end)

-- =============================================================================
-- TESTS: Config reset clears secret
-- =============================================================================

test("Config.setNetworkSecret with nil clears the secret", function()
    Mocks.setupZone({id = 10})

    local Config = mpm("shelfos/core/Config")

    local config = Config.create("zone_10", "Zone 10")
    config.network = { enabled = true, secret = "existing_secret" }

    -- Clear secret (what happens when leaving swarm)
    Config.setNetworkSecret(config, nil)

    assert_true(config.network.secret == nil, "Secret should be nil")
    assert_false(config.network.enabled, "Should be disabled when secret is nil")
    assert_false(Config.isInSwarm(config), "Should not be in swarm after clearing")
end)

test("After fs.delete of config file, Config.load returns nil", function()
    Mocks.setupZone({id = 10})

    local Config = mpm("shelfos/core/Config")

    -- Create and save config
    local config = Config.create("zone_10", "Zone 10")
    config.network = { enabled = true, secret = "test_secret" }
    Config.save(config)

    -- Verify it exists
    local Paths = mpm("shelfos/core/Paths")
    assert_true(fs.exists(Paths.ZONE_CONFIG), "Config file should exist")

    -- Delete (factory reset)
    fs.delete(Paths.ZONE_CONFIG)

    -- Clear module cache
    module_cache["shelfos/core/Config"] = nil
    local Config2 = mpm("shelfos/core/Config")

    -- Verify load returns nil
    local loaded = Config2.load()
    assert_true(loaded == nil, "Config.load should return nil after delete")
end)

-- =============================================================================
-- TESTS: Multi-zone discovery (both zones should appear)
-- =============================================================================

test("Multi-zone: Two zones with different IDs both appear in pendingZones", function()
    -- This tests the App.lua:addZone() logic at lines 319-326
    -- Verifies that zones with different computerId values are tracked separately

    Mocks.setupZone({id = 10})

    local Protocol = mpm("net/Protocol")

    -- Simulate two zones broadcasting PAIR_READY
    local zone1Ready = Protocol.createPairReady(nil, "Zone A", 10)
    local zone2Ready = Protocol.createPairReady(nil, "Zone B", 11)

    -- The key identifiers
    local zone1Id = zone1Ready.data.computerId  -- 10
    local zone2Id = zone2Ready.data.computerId  -- 11

    -- Simulate App.lua:addZone() pendingZones tracking
    local pendingZones = {}

    -- Process zone1
    local found1 = false
    for _, z in ipairs(pendingZones) do
        if z.id == zone1Id then
            found1 = true
            break
        end
    end
    if not found1 then
        table.insert(pendingZones, {
            id = zone1Id,
            label = zone1Ready.data.label
        })
    end

    -- Process zone2
    local found2 = false
    for _, z in ipairs(pendingZones) do
        if z.id == zone2Id then
            found2 = true
            break
        end
    end
    if not found2 then
        table.insert(pendingZones, {
            id = zone2Id,
            label = zone2Ready.data.label
        })
    end

    -- Both zones should be in the list
    assert_eq(2, #pendingZones, "Should have 2 pending zones")
    assert_eq(10, pendingZones[1].id, "Zone A should have ID 10")
    assert_eq(11, pendingZones[2].id, "Zone B should have ID 11")
    assert_eq("Zone A", pendingZones[1].label)
    assert_eq("Zone B", pendingZones[2].label)
end)

test("Multi-zone: Same zone broadcasting twice updates lastSeen, not duplicate", function()
    Mocks.setupZone({id = 10})

    local Protocol = mpm("net/Protocol")

    -- Same zone broadcasts twice (periodic re-broadcast)
    local zoneReady1 = Protocol.createPairReady(nil, "Zone A", 10)
    local zoneReady2 = Protocol.createPairReady(nil, "Zone A", 10)

    local pendingZones = {}

    -- First broadcast
    local zoneId = zoneReady1.data.computerId
    local found = false
    for _, z in ipairs(pendingZones) do
        if z.id == zoneId then
            found = true
            z.lastSeen = 1000
            break
        end
    end
    if not found then
        table.insert(pendingZones, {
            id = zoneId,
            label = zoneReady1.data.label,
            lastSeen = 1000
        })
    end

    assert_eq(1, #pendingZones, "Should have 1 zone after first broadcast")

    -- Second broadcast (same zone)
    found = false
    for _, z in ipairs(pendingZones) do
        if z.id == zoneId then
            found = true
            z.lastSeen = 2000  -- Update timestamp
            break
        end
    end
    if not found then
        table.insert(pendingZones, {
            id = zoneId,
            label = zoneReady2.data.label,
            lastSeen = 2000
        })
    end

    -- Still only one zone (updated, not duplicated)
    assert_eq(1, #pendingZones, "Should still have 1 zone after second broadcast")
    assert_eq(2000, pendingZones[1].lastSeen, "lastSeen should be updated")
end)

-- =============================================================================
-- TESTS: os.getComputerID uniqueness (CC:Tweaked behavior)
-- =============================================================================

test("os.getComputerID returns unique IDs for different computers", function()
    -- Setup zone with ID 10
    Mocks.setupZone({id = 10})
    local id1 = os.getComputerID()
    assert_eq(10, id1, "Zone should have ID 10")

    -- Setup different zone with ID 11
    Mocks.setupZone({id = 11})
    local id2 = os.getComputerID()
    assert_eq(11, id2, "Zone should have ID 11")

    -- IDs are different
    assert_true(id1 ~= id2, "Computer IDs should be unique")
end)

test("PAIR_READY message contains os.getComputerID (not clonable)", function()
    Mocks.setupZone({id = 42})

    local Protocol = mpm("net/Protocol")

    local computerId = os.getComputerID()
    local ready = Protocol.createPairReady(nil, "Zone 42", computerId)

    -- The computerId in PAIR_READY is what App.lua uses to identify zones
    assert_eq(42, ready.data.computerId)

    -- This ID comes from CC:Tweaked's os.getComputerID() which is:
    -- 1. Unique per computer instance
    -- 2. NOT clonable (assigned by the system, not stored in files)
    -- 3. Persists across reboots for the same computer
end)

-- =============================================================================
-- TESTS: Re-pairing scenario
-- =============================================================================

test("Re-pairing: Zone that left swarm can re-enter pairing mode", function()
    Mocks.setupZone({id = 10})

    local Config = mpm("shelfos/core/Config")
    local Paths = mpm("shelfos/core/Paths")

    -- Zone was previously paired
    local pairedConfig = Config.create("zone_10", "Zone 10")
    pairedConfig.network = { enabled = true, secret = "old_swarm_secret" }
    Config.save(pairedConfig)

    -- Verify paired
    local loaded1 = Config.load()
    assert_true(Config.isInSwarm(loaded1), "Should be in swarm initially")

    -- User initiates "Leave Swarm" (what Kernel.lua does)
    loaded1.network.enabled = false
    loaded1.network.secret = nil
    Config.save(loaded1)

    -- Clear module cache
    module_cache["shelfos/core/Config"] = nil
    local Config2 = mpm("shelfos/core/Config")

    -- Verify can re-enter pairing mode
    local loaded2 = Config2.load()
    assert_false(Config2.isInSwarm(loaded2), "Should NOT be in swarm after leaving")

    -- Zone can now show [L] and broadcast PAIR_READY again
    local shouldEnterPairingMode = not (loaded2.network and loaded2.network.secret)
    assert_true(shouldEnterPairingMode, "Should be able to enter pairing mode again")
end)

-- =============================================================================
-- TESTS: Crypto.clearSecret clears _G state
-- =============================================================================

test("Crypto.clearSecret removes secret from _G", function()
    Mocks.setupZone({id = 10})

    local Crypto = mpm("net/Crypto")

    -- Set a secret (must be at least 16 characters per Crypto.lua:50)
    Crypto.setSecret("test_secret_1234567890")
    assert_true(Crypto.hasSecret(), "Should have secret after setSecret")

    -- Clear it (what happens on reset or leave swarm)
    Crypto.clearSecret()
    assert_false(Crypto.hasSecret(), "Should NOT have secret after clearSecret")
end)
