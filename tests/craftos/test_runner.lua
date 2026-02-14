-- CraftOS-PC Test Runner
-- Runs ShelfOS tests inside a real CraftOS environment
-- Usage: craftos --headless --mount-ro /workspace=<mpm-packages-path> --script /workspace/tests/craftos/test_runner.lua

local WORKSPACE = "/workspace"

-- Simple test framework
local tests = {}
local passed = 0
local failed = 0
local errors = {}

local function test(name, fn)
    table.insert(tests, { name = name, fn = fn })
end

local function assert_true(value, msg)
    if not value then
        error(msg or "Expected true, got " .. tostring(value))
    end
end

local function assert_false(value, msg)
    if value then
        error(msg or "Expected false, got " .. tostring(value))
    end
end

local function assert_eq(expected, actual, msg)
    if expected ~= actual then
        error((msg or "Values differ") ..
              string.format(" (expected=%s, actual=%s)", tostring(expected), tostring(actual)))
    end
end

local function assert_not_nil(value, msg)
    if value == nil then
        error(msg or "Expected non-nil value")
    end
end

-- Setup mpm loader
local function setup_mpm()
    local module_cache = {}

    _G.mpm = function(name)
        if not module_cache[name] then
            local path = WORKSPACE .. "/" .. name .. ".lua"
            if not fs.exists(path) then
                error("Module not found: " .. name .. " at " .. path)
            end
            local fn, err = loadfile(path)
            if not fn then
                error("Failed to load " .. name .. ": " .. tostring(err))
            end
            module_cache[name] = fn()
        end
        return module_cache[name]
    end
end

-- =============================================================================
-- TESTS
-- =============================================================================

test("CraftOS environment is valid", function()
    assert_not_nil(os.getComputerID, "os.getComputerID should exist")
    assert_not_nil(os.pullEvent, "os.pullEvent should exist")
    assert_not_nil(peripheral, "peripheral should exist")
    assert_not_nil(rednet, "rednet should exist")
    assert_not_nil(keys, "keys table should exist")
    assert_not_nil(colors, "colors table should exist")
end)

test("Workspace is mounted", function()
    assert_true(fs.exists(WORKSPACE), "Workspace should be mounted")
    assert_true(fs.isDir(WORKSPACE), "Workspace should be a directory")
end)

test("mpm loader works", function()
    setup_mpm()
    assert_not_nil(_G.mpm, "mpm should be defined")
end)

test("Protocol module loads", function()
    setup_mpm()
    local Protocol = mpm("net/Protocol")
    assert_not_nil(Protocol, "Protocol should load")
    assert_not_nil(Protocol.MessageType, "Protocol.MessageType should exist")
    assert_not_nil(Protocol.MessageType.PAIR_READY, "PAIR_READY should be defined")
end)

test("Crypto module loads", function()
    setup_mpm()
    local Crypto = mpm("net/Crypto")
    assert_not_nil(Crypto, "Crypto should load")
    assert_not_nil(Crypto.generateSecret, "generateSecret should exist")
    assert_not_nil(Crypto.signWith, "signWith should exist")
end)

test("Pairing module loads", function()
    setup_mpm()
    local Pairing = mpm("net/Pairing")
    assert_not_nil(Pairing, "Pairing should load")
    assert_not_nil(Pairing.generateCode, "generateCode should exist")
    assert_not_nil(Pairing.acceptFromPocket, "acceptFromPocket should exist")
    assert_not_nil(Pairing.deliverToPending, "deliverToPending should exist")
end)

test("Pairing.generateCode produces valid format", function()
    setup_mpm()
    local Pairing = mpm("net/Pairing")
    local code = Pairing.generateCode()

    assert_eq(9, #code, "Code should be 9 characters (XXXX-XXXX)")
    assert_eq("-", code:sub(5, 5), "Code should have dash at position 5")

    local allowed = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    for i = 1, #code do
        if i ~= 5 then
            local char = code:sub(i, i)
            assert_true(allowed:find(char, 1, true) ~= nil,
                       "Invalid character in code: " .. char)
        end
    end
end)

test("Crypto.generateSecret produces valid secret", function()
    setup_mpm()
    local Crypto = mpm("net/Crypto")
    local secret = Crypto.generateSecret()

    assert_not_nil(secret, "Secret should be generated")
    assert_true(#secret >= 32, "Secret should be at least 32 characters")
end)

test("Crypto signWith/verifyWith roundtrip", function()
    setup_mpm()
    local Crypto = mpm("net/Crypto")

    local key = "test-ephemeral-key"
    local data = { message = "Hello", value = 42 }

    local signed = Crypto.signWith(data, key)
    assert_not_nil(signed, "Signed result should not be nil")
    assert_not_nil(signed.s, "Should have signature")

    -- verifyWith returns: success (bool), data, error
    local success, verified, err = Crypto.verifyWith(signed, key)
    assert_true(success, "Should verify with correct key: " .. tostring(err))
    assert_not_nil(verified, "Verified data should not be nil")
    assert_eq("Hello", verified.message, "Data should match after verify")
end)

test("Crypto signWith/verifyWith rejects wrong key", function()
    setup_mpm()
    local Crypto = mpm("net/Crypto")

    local data = { secret = "classified" }
    local signed = Crypto.signWith(data, "correct-key")

    -- verifyWith returns: success (bool), data, error
    local success, _, _ = Crypto.verifyWith(signed, "wrong-key")
    assert_false(success, "Should reject wrong key")
end)

test("Protocol.createPairReady structure", function()
    setup_mpm()
    local Protocol = mpm("net/Protocol")

    local ready = Protocol.createPairReady(nil, "Test Zone", 42)

    assert_eq(Protocol.MessageType.PAIR_READY, ready.type, "Type should be PAIR_READY")
    assert_eq("Test Zone", ready.data.label, "Label should match")
    assert_eq(42, ready.data.computerId, "ComputerId should match")
end)

test("Protocol.createPairDeliver structure", function()
    setup_mpm()
    local Protocol = mpm("net/Protocol")

    local deliver = Protocol.createPairDeliver("secret123", "zone_42")

    assert_eq(Protocol.MessageType.PAIR_DELIVER, deliver.type, "Type should be PAIR_DELIVER")
    assert_eq("secret123", deliver.data.secret, "Secret should match")
    assert_eq("zone_42", deliver.data.zoneId, "ZoneId should match")
end)

test("keys table has expected scancodes", function()
    -- CC:Tweaked key scancodes
    assert_eq(28, keys.enter, "keys.enter should be 28")
    assert_eq(16, keys.q, "keys.q should be 16")
    assert_eq(200, keys.up, "keys.up should be 200")
    assert_eq(208, keys.down, "keys.down should be 208")
end)

test("AEInterface module loads", function()
    setup_mpm()
    local AEInterface = mpm("peripherals/AEInterface")
    assert_not_nil(AEInterface, "AEInterface should load")
    assert_not_nil(AEInterface.exists, "exists should exist")
    assert_not_nil(AEInterface.find, "find should exist")
end)

test("BaseView module loads", function()
    setup_mpm()
    local BaseView = mpm("views/BaseView")
    assert_not_nil(BaseView, "BaseView should load")
    assert_not_nil(BaseView.custom, "custom should exist")
    assert_not_nil(BaseView.grid, "grid should exist")
    assert_not_nil(BaseView.list, "list should exist")
end)

-- =============================================================================
-- ADVANCED PAIRING TESTS (Using real CC:Tweaked APIs)
-- =============================================================================

test("Full pairing message flow simulation", function()
    setup_mpm()
    local Protocol = mpm("net/Protocol")
    local Crypto = mpm("net/Crypto")
    local Pairing = mpm("net/Pairing")

    -- Simulate the complete message exchange
    local displayCode = Pairing.generateCode()
    local swarmSecret = Crypto.generateSecret()
    local zoneId = "zone_" .. os.getComputerID()

    -- 1. Zone creates PAIR_READY
    local ready = Protocol.createPairReady(nil, "Test Zone", os.getComputerID())
    assert_eq(Protocol.MessageType.PAIR_READY, ready.type)

    -- 2. Pocket creates and signs PAIR_DELIVER with display code
    local deliver = Protocol.createPairDeliver(swarmSecret, zoneId)
    local signedDeliver = Crypto.wrapWith(deliver, displayCode)
    assert_not_nil(signedDeliver.s, "PAIR_DELIVER should be signed")

    -- 3. Zone verifies PAIR_DELIVER with its display code
    -- unwrapWith returns: data, error (not success, data, error)
    local unwrapped, err = Crypto.unwrapWith(signedDeliver, displayCode)
    assert_not_nil(unwrapped, "Zone should verify with display code: " .. tostring(err))
    assert_eq(Protocol.MessageType.PAIR_DELIVER, unwrapped.type)
    assert_eq(swarmSecret, unwrapped.data.secret)

    -- 4. Zone creates PAIR_COMPLETE
    local complete = Protocol.createPairComplete("Test Zone")
    assert_eq(Protocol.MessageType.PAIR_COMPLETE, complete.type)
end)

test("Pairing rejects wrong display code", function()
    setup_mpm()
    local Protocol = mpm("net/Protocol")
    local Crypto = mpm("net/Crypto")
    local Pairing = mpm("net/Pairing")

    local realCode = Pairing.generateCode()
    local wrongCode = Pairing.generateCode()  -- Different code

    -- Pocket signs with wrong code
    local deliver = Protocol.createPairDeliver("secret", "zone")
    local signedDeliver = Crypto.wrapWith(deliver, wrongCode)

    -- Zone tries to verify with real code
    local success, _, _ = Crypto.unwrapWith(signedDeliver, realCode)
    assert_false(success, "Should reject wrong display code")
end)

test("wrapWith/unwrapWith roundtrip with pairing data", function()
    setup_mpm()
    local Crypto = mpm("net/Crypto")

    local displayCode = "ABCD-1234"
    local credentials = {
        swarmSecret = "secret-abc-123",
        zoneId = "zone_42",
        swarmFingerprint = "FP-XYZ-789"
    }

    local wrapped = Crypto.wrapWith(credentials, displayCode)
    -- unwrapWith returns: data, error (2 values)
    local unwrapped, err = Crypto.unwrapWith(wrapped, displayCode)

    assert_not_nil(unwrapped, "Should unwrap successfully: " .. tostring(err))
    assert_eq(credentials.swarmSecret, unwrapped.swarmSecret)
    assert_eq(credentials.zoneId, unwrapped.zoneId)
    assert_eq(credentials.swarmFingerprint, unwrapped.swarmFingerprint)
end)

test("os.epoch provides valid timestamps", function()
    local t1 = os.epoch("utc")
    sleep(0.1)
    local t2 = os.epoch("utc")

    assert_true(t1 > 0, "Timestamp should be positive")
    assert_true(t2 > t1, "Time should advance")
end)

test("os.startTimer returns valid timer ID", function()
    local timerId = os.startTimer(0.1)
    assert_true(type(timerId) == "number", "Timer ID should be a number")
    assert_true(timerId > 0, "Timer ID should be positive")

    -- Wait for timer event
    local event, id = os.pullEvent("timer")
    assert_eq("timer", event)
    assert_eq(timerId, id, "Timer ID should match")
end)

test("textutils.serialize/unserialize roundtrip", function()
    local data = {
        type = "PAIR_READY",
        data = {
            label = "Zone A",
            computerId = 42
        },
        timestamp = os.epoch("utc")
    }

    local serialized = textutils.serialize(data)
    assert_true(type(serialized) == "string", "Should serialize to string")

    local deserialized = textutils.unserialize(serialized)
    assert_eq(data.type, deserialized.type)
    assert_eq(data.data.label, deserialized.data.label)
    assert_eq(data.data.computerId, deserialized.data.computerId)
end)

test("parallel.waitForAny executes multiple coroutines", function()
    local results = {}

    parallel.waitForAny(
        function()
            results.a = "executed"
            while true do sleep(1) end  -- Keep running
        end,
        function()
            sleep(0.1)
            results.b = "executed"
            -- This one finishes first, stopping all
        end
    )

    -- At least one should have executed
    assert_true(results.a == "executed" or results.b == "executed",
                "At least one coroutine should execute")
end)

-- =============================================================================
-- RUNNER
-- =============================================================================

local function run_tests()
    print("")
    print("=== CraftOS-PC Integration Tests ===")
    print("")

    for _, t in ipairs(tests) do
        local ok, err = pcall(t.fn)
        if ok then
            passed = passed + 1
            print("[PASS] " .. t.name)
        else
            failed = failed + 1
            table.insert(errors, { name = t.name, error = err })
            print("[FAIL] " .. t.name)
            print("       " .. tostring(err))
        end
    end

    print("")
    print("=== Results ===")
    print(string.format("Passed: %d, Failed: %d, Total: %d", passed, failed, #tests))

    if failed > 0 then
        print("")
        print("Failures:")
        for _, e in ipairs(errors) do
            print("  - " .. e.name .. ": " .. e.error)
        end
    end

    print("")

    -- Exit with appropriate code
    if failed > 0 then
        print("TESTS FAILED")
    else
        print("ALL TESTS PASSED")
    end
end

-- Run and shutdown
run_tests()
os.shutdown()
