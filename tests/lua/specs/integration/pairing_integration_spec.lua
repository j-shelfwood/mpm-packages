-- Pairing Integration Tests
-- Tests the full pairing flow with realistic peripheral mocks

local root = _G.TEST_ROOT or "."

-- Setup module loader
local module_cache = {}
_G.mpm = function(name)
    if not module_cache[name] then
        module_cache[name] = dofile(root .. "/mpm-packages/" .. name .. ".lua")
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
-- TESTS
-- =============================================================================

test("Pocket: peripheral.find('modem') returns ender modem", function()
    local env = Mocks.setupPocket({id = 1})

    local modem = peripheral.find("modem")
    assert_not_nil(modem, "Should find modem")
    assert_true(modem.isWireless(), "Ender modem should report as wireless")
end)

test("Pocket: peripheral.getName returns 'back' for ender modem", function()
    local env = Mocks.setupPocket({id = 1})

    local modem = peripheral.find("modem")
    local name = peripheral.getName(modem)
    assert_eq("back", name, "Ender modem should be on 'back'")
end)

test("Pocket: rednet.open succeeds with valid modem", function()
    local env = Mocks.setupPocket({id = 1})

    -- Should not error
    rednet.open("back")
    assert_true(rednet.isOpen("back"), "Modem should be open")
end)

test("Pocket: rednet.open fails with invalid modem name", function()
    local env = Mocks.setupPocket({id = 1})

    local ok, err = pcall(function()
        rednet.open("invalid_modem")
    end)
    assert_false(ok, "Should fail with invalid modem")
end)

test("Zone: peripheral.find('modem') returns wireless modem", function()
    local env = Mocks.setupZone({id = 10, modemName = "top"})

    local modem = peripheral.find("modem")
    assert_not_nil(modem, "Should find modem")

    local name = peripheral.getName(modem)
    assert_eq("top", name, "Modem should be on configured side")
end)

test("Zone: peripheral.find('monitor') returns monitor", function()
    local env = Mocks.setupZone({id = 10, monitors = 2})

    local mon = peripheral.find("monitor")
    assert_not_nil(mon, "Should find monitor")

    local w, h = mon.getSize()
    assert_eq(51, w, "Default width should be 51")
    assert_eq(19, h, "Default height should be 19")
end)

test("Zone: ME Bridge is attached and functional", function()
    local env = Mocks.setupZone({id = 10})

    local bridge = peripheral.find("me_bridge")
    assert_not_nil(bridge, "Should find ME Bridge")
    assert_true(bridge.isConnected(), "Bridge should be connected")

    local items = bridge.getItems()
    assert_true(#items > 0, "Should have items")
end)

test("Protocol: PAIR_READY message structure is correct", function()
    Mocks.setupZone({id = 10})

    local Protocol = mpm("net/Protocol")
    local ready = Protocol.createPairReady(nil, "Test Zone", 10)

    assert_eq(Protocol.MessageType.PAIR_READY, ready.type)
    assert_eq("Test Zone", ready.data.label)
    assert_eq(10, ready.data.computerId)
end)

test("Crypto: wrapWith/unwrapWith roundtrip with display code", function()
    Mocks.setupZone({id = 10})

    local Crypto = mpm("net/Crypto")
    local Protocol = mpm("net/Protocol")

    local displayCode = "ABCD-EFGH"
    local deliver = Protocol.createPairDeliver("secret123", "zone_10")

    local wrapped = Crypto.wrapWith(deliver, displayCode)
    assert_not_nil(wrapped.v, "Should have version")
    assert_not_nil(wrapped.s, "Should have signature")
    assert_not_nil(wrapped.p, "Should have payload")

    local unwrapped, err = Crypto.unwrapWith(wrapped, displayCode)
    assert_not_nil(unwrapped, "Should unwrap with correct code: " .. tostring(err))
    assert_eq(Protocol.MessageType.PAIR_DELIVER, unwrapped.type)
    assert_eq("secret123", unwrapped.data.secret)
end)

test("Crypto: unwrapWith rejects wrong display code", function()
    Mocks.setupZone({id = 10})

    local Crypto = mpm("net/Crypto")
    local Protocol = mpm("net/Protocol")

    local correctCode = "ABCD-EFGH"
    local wrongCode = "WXYZ-1234"

    local deliver = Protocol.createPairDeliver("secret123", "zone_10")
    local wrapped = Crypto.wrapWith(deliver, correctCode)

    local unwrapped, err = Crypto.unwrapWith(wrapped, wrongCode)
    assert_true(unwrapped == nil, "Should NOT unwrap with wrong code")
end)

test("Pairing: generateCode produces XXXX-XXXX format", function()
    Mocks.setupZone({id = 10})

    local Pairing = mpm("net/Pairing")
    local code = Pairing.generateCode()

    assert_eq(9, #code, "Code should be 9 characters")
    assert_eq("-", code:sub(5, 5), "Code should have dash at position 5")

    -- Check allowed characters
    local allowed = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    for i = 1, #code do
        if i ~= 5 then
            local char = code:sub(i, i)
            assert_true(allowed:find(char, 1, true), "Invalid character: " .. char)
        end
    end
end)

test("Full flow: Zone broadcasts PAIR_READY on rednet", function()
    local env = Mocks.setupZone({id = 10, modemName = "top"})

    local Protocol = mpm("net/Protocol")
    local Pairing = mpm("net/Pairing")

    rednet.open("top")

    local ready = Protocol.createPairReady(nil, "Test Zone", 10)
    rednet.broadcast(ready, Pairing.PROTOCOL)

    local log = rednet._getBroadcastLog()
    assert_eq(1, #log, "Should have one broadcast")
    assert_eq(Pairing.PROTOCOL, log[1].protocol)
    assert_eq(Protocol.MessageType.PAIR_READY, log[1].message.type)
end)

test("Full flow: Pocket receives PAIR_READY and sends signed PAIR_DELIVER", function()
    local pocket = Mocks.setupPocket({id = 1})

    local Protocol = mpm("net/Protocol")
    local Crypto = mpm("net/Crypto")
    local Pairing = mpm("net/Pairing")

    -- Zone sends PAIR_READY
    local zoneId = 10
    local ready = Protocol.createPairReady(nil, "Test Zone", zoneId)
    rednet._queueMessage(zoneId, ready, Pairing.PROTOCOL)

    -- Pocket opens modem and receives
    rednet.open("back")
    local sender, msg, protocol = rednet.receive(Pairing.PROTOCOL, 1)

    assert_eq(zoneId, sender, "Should receive from zone")
    assert_eq(Protocol.MessageType.PAIR_READY, msg.type)

    -- Pocket sends signed PAIR_DELIVER
    local displayCode = "TEST-CODE"
    local deliver = Protocol.createPairDeliver("swarm_secret_xyz", "zone_10")
    local signed = Crypto.wrapWith(deliver, displayCode)

    rednet.send(zoneId, signed, Pairing.PROTOCOL)

    local sendLog = rednet._getSendLog()
    assert_eq(1, #sendLog, "Should have one send")
    assert_eq(zoneId, sendLog[1].recipient)
    assert_not_nil(sendLog[1].message.s, "Message should be signed")
end)

test("Full flow: Zone verifies PAIR_DELIVER with display code", function()
    local env = Mocks.setupZone({id = 10})

    local Protocol = mpm("net/Protocol")
    local Crypto = mpm("net/Crypto")
    local Pairing = mpm("net/Pairing")

    local displayCode = "ABCD-1234"
    local pocketId = 1

    -- Pocket sends signed PAIR_DELIVER
    local deliver = Protocol.createPairDeliver("swarm_secret_xyz", "zone_10")
    deliver.data.credentials = {
        swarmSecret = "swarm_secret_xyz",
        zoneId = "zone_10",
        swarmFingerprint = "FP-TEST-001"
    }
    local signed = Crypto.wrapWith(deliver, displayCode)

    rednet._queueMessage(pocketId, signed, Pairing.PROTOCOL)

    -- Zone receives and verifies
    rednet.open("top")
    local sender, envelope, protocol = rednet.receive(Pairing.PROTOCOL, 1)

    assert_eq(pocketId, sender)
    assert_not_nil(envelope.s, "Should be signed envelope")

    -- Verify with display code
    local unwrapped, err = Crypto.unwrapWith(envelope, displayCode)
    assert_not_nil(unwrapped, "Should verify with correct code: " .. tostring(err))
    assert_eq(Protocol.MessageType.PAIR_DELIVER, unwrapped.type)

    -- Extract credentials
    local creds = unwrapped.data.credentials
    assert_eq("swarm_secret_xyz", creds.swarmSecret)
    assert_eq("zone_10", creds.zoneId)
    assert_eq("FP-TEST-001", creds.swarmFingerprint)
end)

test("Security: Attacker cannot forge PAIR_DELIVER without display code", function()
    local env = Mocks.setupZone({id = 10})

    local Protocol = mpm("net/Protocol")
    local Crypto = mpm("net/Crypto")

    local realCode = "REAL-CODE"
    local attackerCode = "FAKE-CODE"

    -- Attacker tries to send PAIR_DELIVER signed with wrong code
    local maliciousDeliver = Protocol.createPairDeliver("attacker_secret", "zone_10")
    local attackerSigned = Crypto.wrapWith(maliciousDeliver, attackerCode)

    -- Zone tries to verify with real display code
    local result, err = Crypto.unwrapWith(attackerSigned, realCode)
    assert_true(result == nil, "Should reject message signed with wrong code")
end)
