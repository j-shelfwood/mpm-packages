-- End-to-End Pairing Integration Test
-- Simulates BOTH pocket and zone computers with a virtual network
-- Messages actually flow between simulated computers

local root = _G.TEST_ROOT or "."

-- Setup module loader
local module_cache = {}
_G.mpm = function(name)
    if not module_cache[name] then
        module_cache[name] = dofile(root .. "/mpm-packages/" .. name .. ".lua")
    end
    return module_cache[name]
end

-- Load modules
local Protocol = mpm("net/Protocol")
local Crypto = mpm("net/Crypto")
local Pairing = mpm("net/Pairing")

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

local function assert_not_nil(value, msg)
    if value == nil then error(msg or "Expected non-nil value") end
end

-- =============================================================================
-- VIRTUAL NETWORK SIMULATOR
-- =============================================================================
-- Simulates rednet communication between multiple "computers"
-- Each computer has its own ID and can send/receive messages

local VirtualNetwork = {}
VirtualNetwork.__index = VirtualNetwork

function VirtualNetwork.new()
    local self = setmetatable({}, VirtualNetwork)
    self.computers = {}  -- id -> {inbox = {}, outbox = {}}
    self.broadcasts = {} -- {sender, msg, protocol}
    return self
end

function VirtualNetwork:register(computerId)
    self.computers[computerId] = {
        inbox = {},
        outbox = {},
        modemOpen = false
    }
end

function VirtualNetwork:send(fromId, toId, message, protocol)
    if self.computers[toId] then
        table.insert(self.computers[toId].inbox, {
            sender = fromId,
            message = message,
            protocol = protocol
        })
    end
end

function VirtualNetwork:broadcast(fromId, message, protocol)
    table.insert(self.broadcasts, {
        sender = fromId,
        message = message,
        protocol = protocol
    })
    -- Deliver to all other computers
    for id, computer in pairs(self.computers) do
        if id ~= fromId and computer.modemOpen then
            table.insert(computer.inbox, {
                sender = fromId,
                message = message,
                protocol = protocol
            })
        end
    end
end

function VirtualNetwork:receive(computerId, protocolFilter)
    local computer = self.computers[computerId]
    if not computer then return nil end

    for i, msg in ipairs(computer.inbox) do
        if not protocolFilter or msg.protocol == protocolFilter then
            table.remove(computer.inbox, i)
            return msg.sender, msg.message, msg.protocol
        end
    end
    return nil
end

function VirtualNetwork:openModem(computerId)
    if self.computers[computerId] then
        self.computers[computerId].modemOpen = true
    end
end

function VirtualNetwork:closeModem(computerId)
    if self.computers[computerId] then
        self.computers[computerId].modemOpen = false
    end
end

-- =============================================================================
-- COMPUTER SIMULATOR
-- =============================================================================
-- Creates a mock environment for a single computer

local function createComputerEnv(network, computerId, computerLabel, config)
    config = config or {}
    local modemName = config.modemName or "back"
    local modemOpen = false
    local currentTime = config.startTime or 1000000
    local eventQueue = {}

    local env = {
        computerId = computerId,
        computerLabel = computerLabel,
        sentMessages = {},
        receivedMessages = {},
        displayCode = nil,  -- Captured from onDisplayCode callback
    }

    -- Peripheral mock
    env.peripheral = {
        find = function(kind)
            if kind == "modem" then
                return {
                    isWireless = function() return true end
                }
            end
            return nil
        end,
        getName = function(obj)
            return modemName
        end
    }

    -- Rednet mock
    env.rednet = {
        isOpen = function(name)
            if name then return modemOpen and name == modemName end
            return modemOpen
        end,
        open = function(name)
            modemOpen = true
            network:openModem(computerId)
        end,
        close = function(name)
            modemOpen = false
            network:closeModem(computerId)
        end,
        broadcast = function(msg, protocol)
            table.insert(env.sentMessages, {type = "broadcast", msg = msg, protocol = protocol})
            network:broadcast(computerId, msg, protocol)
        end,
        send = function(toId, msg, protocol)
            table.insert(env.sentMessages, {type = "send", to = toId, msg = msg, protocol = protocol})
            network:send(computerId, toId, msg, protocol)
        end
    }

    -- OS mock
    env.os_overrides = {
        getComputerID = function() return computerId end,
        getComputerLabel = function() return computerLabel end,
        epoch = function(kind)
            currentTime = currentTime + 50
            return currentTime
        end,
        startTimer = function(seconds)
            return math.random(1, 1000)
        end,
        pullEvent = function(filter)
            -- Check for queued events first
            if #eventQueue > 0 then
                local event = table.remove(eventQueue, 1)
                if not filter or event[1] == filter then
                    return table.unpack(event)
                end
            end

            -- Check network inbox
            local sender, msg, protocol = network:receive(computerId, nil)
            if sender then
                table.insert(env.receivedMessages, {sender = sender, msg = msg, protocol = protocol})
                return "rednet_message", sender, msg, protocol
            end

            -- Return timer to keep event loop moving
            return "timer", math.random(1, 1000)
        end
    }

    -- Keys mock
    env.keys = {
        q = 16,
        up = 200,
        down = 208,
        enter = 28,
        one = 2,
        two = 3
    }

    -- Queue an event for this computer
    env.queueEvent = function(...)
        table.insert(eventQueue, {...})
    end

    return env
end

-- Apply environment overrides
local function withEnv(env, fn)
    local restore = {}
    local os_restore = {}

    -- Save and override globals
    for _, key in ipairs({"peripheral", "rednet", "keys"}) do
        restore[key] = _G[key]
        _G[key] = env[key]
    end

    -- Save and override os functions
    for name, fn_impl in pairs(env.os_overrides) do
        os_restore[name] = os[name]
        os[name] = fn_impl
    end

    local ok, result = pcall(fn)

    -- Restore os
    for name, original in pairs(os_restore) do
        os[name] = original
    end

    -- Restore globals
    for key, original in pairs(restore) do
        _G[key] = original
    end

    if not ok then error(result) end
    return result
end

-- =============================================================================
-- TESTS
-- =============================================================================

test("E2E: Full pairing flow - zone and pocket exchange credentials", function()
    -- Create virtual network
    local network = VirtualNetwork.new()

    -- Create zone computer (ID: 10)
    local zoneId = 10
    local zoneEnv = createComputerEnv(network, zoneId, "Zone Computer", {
        modemName = "top",
        startTime = 1000000
    })
    network:register(zoneId)

    -- Create pocket computer (ID: 1)
    local pocketId = 1
    local pocketEnv = createComputerEnv(network, pocketId, "Pocket Controller", {
        modemName = "back",
        startTime = 1000000
    })
    network:register(pocketId)

    -- Test secret and credentials
    local testSecret = "test_swarm_secret_xyz123"
    local testZoneId = "zone_" .. zoneId .. "_assigned"

    -- Variables to capture results
    local zoneResult = {}
    local pocketResult = {}
    local capturedDisplayCode = nil

    -- STEP 0: Pocket opens modem first (listening for zones)
    withEnv(pocketEnv, function()
        rednet.open("back")
    end)

    -- STEP 1: Zone starts pairing and captures display code
    withEnv(zoneEnv, function()
        -- Generate display code (this is what zone shows on screen)
        capturedDisplayCode = Pairing.generateCode()
        zoneEnv.displayCode = capturedDisplayCode

        -- Open modem and broadcast PAIR_READY
        rednet.open("top")
        local ready = Protocol.createPairReady(nil, "Zone Computer", zoneId)
        rednet.broadcast(ready, Pairing.PROTOCOL)
    end)

    assert_not_nil(capturedDisplayCode, "Zone should generate display code")
    assert_eq(9, #capturedDisplayCode, "Display code should be XXXX-XXXX format")

    -- STEP 2: Pocket receives PAIR_READY
    local receivedReady = nil
    withEnv(pocketEnv, function()
        rednet.open("back")
        local sender, msg, protocol = network:receive(pocketId, Pairing.PROTOCOL)
        if sender and msg then
            receivedReady = {sender = sender, msg = msg}
        end
    end)

    assert_not_nil(receivedReady, "Pocket should receive PAIR_READY")
    assert_eq(Protocol.MessageType.PAIR_READY, receivedReady.msg.type)
    assert_eq(zoneId, receivedReady.sender)
    assert_eq("Zone Computer", receivedReady.msg.data.label)

    -- STEP 3: Pocket sends signed PAIR_DELIVER using display code
    withEnv(pocketEnv, function()
        local deliver = Protocol.createPairDeliver(testSecret, testZoneId)
        deliver.data.credentials = {
            swarmSecret = testSecret,
            zoneId = testZoneId,
            swarmFingerprint = "TEST-FP-001"
        }

        -- Sign with display code (simulating user entering the code they see)
        local signedEnvelope = Crypto.wrapWith(deliver, capturedDisplayCode)
        rednet.send(zoneId, signedEnvelope, Pairing.PROTOCOL)

        pocketResult.sent = true
    end)

    assert_true(pocketResult.sent, "Pocket should send PAIR_DELIVER")

    -- STEP 4: Zone receives and verifies PAIR_DELIVER
    withEnv(zoneEnv, function()
        local sender, envelope, protocol = network:receive(zoneId, Pairing.PROTOCOL)

        if sender and envelope then
            zoneResult.receivedEnvelope = true

            -- Verify signature with display code
            local unwrapped, err = Crypto.unwrapWith(envelope, capturedDisplayCode)
            if unwrapped then
                zoneResult.verified = true
                zoneResult.messageType = unwrapped.type
                zoneResult.secret = unwrapped.data.secret or
                                   (unwrapped.data.credentials and unwrapped.data.credentials.swarmSecret)
                zoneResult.zoneId = unwrapped.data.zoneId or
                                   (unwrapped.data.credentials and unwrapped.data.credentials.zoneId)

                -- Send PAIR_COMPLETE
                local complete = Protocol.createPairComplete("Zone Computer")
                rednet.send(pocketId, complete, Pairing.PROTOCOL)
                zoneResult.sentComplete = true
            else
                zoneResult.verifyError = err
            end
        end
    end)

    assert_true(zoneResult.receivedEnvelope, "Zone should receive envelope")
    assert_true(zoneResult.verified, "Zone should verify signature: " .. tostring(zoneResult.verifyError))
    assert_eq(Protocol.MessageType.PAIR_DELIVER, zoneResult.messageType)
    assert_eq(testSecret, zoneResult.secret, "Zone should extract secret")
    assert_eq(testZoneId, zoneResult.zoneId, "Zone should extract zoneId")
    assert_true(zoneResult.sentComplete, "Zone should send PAIR_COMPLETE")

    -- STEP 5: Pocket receives PAIR_COMPLETE
    withEnv(pocketEnv, function()
        local sender, msg, protocol = network:receive(pocketId, Pairing.PROTOCOL)
        if sender and msg then
            pocketResult.receivedComplete = true
            pocketResult.completeType = msg.type
        end
    end)

    assert_true(pocketResult.receivedComplete, "Pocket should receive PAIR_COMPLETE")
    assert_eq(Protocol.MessageType.PAIR_COMPLETE, pocketResult.completeType)
end)

test("E2E: Wrong display code fails verification", function()
    local network = VirtualNetwork.new()

    local zoneId = 20
    local pocketId = 2

    network:register(zoneId)
    network:register(pocketId)

    local zoneEnv = createComputerEnv(network, zoneId, "Zone", {modemName = "top"})
    local pocketEnv = createComputerEnv(network, pocketId, "Pocket", {modemName = "back"})

    -- Zone's actual display code
    local realCode = "REAL-CODE"

    -- Attacker/typo: wrong code entered on pocket
    local wrongCode = "WRNG-CODE"

    -- Pocket sends with wrong code
    withEnv(pocketEnv, function()
        rednet.open("back")
        local deliver = Protocol.createPairDeliver("stolen_secret", "zone_20")
        local signedEnvelope = Crypto.wrapWith(deliver, wrongCode)
        rednet.send(zoneId, signedEnvelope, Pairing.PROTOCOL)
    end)

    -- Zone tries to verify with real code
    local verifyResult = nil
    withEnv(zoneEnv, function()
        rednet.open("top")
        local sender, envelope, protocol = network:receive(zoneId, Pairing.PROTOCOL)

        if envelope then
            local unwrapped, err = Crypto.unwrapWith(envelope, realCode)
            verifyResult = {
                success = unwrapped ~= nil,
                error = err
            }
        end
    end)

    assert_not_nil(verifyResult, "Zone should receive message")
    assert_true(not verifyResult.success, "Verification should FAIL with wrong code")
end)

test("E2E: Multiple zones can pair with same pocket", function()
    local network = VirtualNetwork.new()

    local pocketId = 1
    local zone1Id = 10
    local zone2Id = 11

    network:register(pocketId)
    network:register(zone1Id)
    network:register(zone2Id)

    local pocketEnv = createComputerEnv(network, pocketId, "Pocket", {modemName = "back"})
    local zone1Env = createComputerEnv(network, zone1Id, "Zone 1", {modemName = "top"})
    local zone2Env = createComputerEnv(network, zone2Id, "Zone 2", {modemName = "top"})

    local zone1Code = "ZN1A-CODE"
    local zone2Code = "ZN2B-CODE"

    local swarmSecret = "shared_swarm_secret"

    -- Pair zone 1
    withEnv(pocketEnv, function()
        rednet.open("back")
        local deliver = Protocol.createPairDeliver(swarmSecret, "zone_10")
        local signed = Crypto.wrapWith(deliver, zone1Code)
        rednet.send(zone1Id, signed, Pairing.PROTOCOL)
    end)

    local zone1Result = nil
    withEnv(zone1Env, function()
        rednet.open("top")
        local _, envelope = network:receive(zone1Id, Pairing.PROTOCOL)
        local unwrapped = Crypto.unwrapWith(envelope, zone1Code)
        zone1Result = unwrapped and unwrapped.data.secret
    end)

    assert_eq(swarmSecret, zone1Result, "Zone 1 should receive secret")

    -- Pair zone 2 (different code)
    withEnv(pocketEnv, function()
        local deliver = Protocol.createPairDeliver(swarmSecret, "zone_11")
        local signed = Crypto.wrapWith(deliver, zone2Code)
        rednet.send(zone2Id, signed, Pairing.PROTOCOL)
    end)

    local zone2Result = nil
    withEnv(zone2Env, function()
        rednet.open("top")
        local _, envelope = network:receive(zone2Id, Pairing.PROTOCOL)
        local unwrapped = Crypto.unwrapWith(envelope, zone2Code)
        zone2Result = unwrapped and unwrapped.data.secret
    end)

    assert_eq(swarmSecret, zone2Result, "Zone 2 should receive same swarm secret")
end)

test("E2E: Broadcast reaches all open modems", function()
    local network = VirtualNetwork.new()

    local broadcasterId = 1
    local listener1Id = 10
    local listener2Id = 11
    local closedId = 12  -- Modem closed

    network:register(broadcasterId)
    network:register(listener1Id)
    network:register(listener2Id)
    network:register(closedId)

    -- Open modems for listeners 1 and 2
    network:openModem(listener1Id)
    network:openModem(listener2Id)
    -- closedId modem stays closed

    -- Broadcast
    network:broadcast(broadcasterId, {type = "test", data = "hello"}, "test_proto")

    -- Check delivery
    local msg1 = network:receive(listener1Id, "test_proto")
    local msg2 = network:receive(listener2Id, "test_proto")
    local msg3 = network:receive(closedId, "test_proto")

    assert_not_nil(msg1, "Listener 1 should receive broadcast")
    assert_not_nil(msg2, "Listener 2 should receive broadcast")
    assert_true(msg3 == nil, "Closed modem should NOT receive broadcast")
end)

test("E2E: Credential extraction matches SwarmAuthority format", function()
    local network = VirtualNetwork.new()

    local pocketId = 1
    local zoneId = 10

    network:register(pocketId)
    network:register(zoneId)

    local pocketEnv = createComputerEnv(network, pocketId, "Pocket", {modemName = "back"})
    local zoneEnv = createComputerEnv(network, zoneId, "Zone", {modemName = "top"})

    local displayCode = "TEST-1234"

    -- Full credentials as SwarmAuthority would issue them
    local fullCredentials = {
        zoneId = "zone_10_abc123",
        zoneSecret = "zone_specific_secret",
        swarmId = "swarm_main_xyz",
        swarmSecret = "shared_swarm_secret_456",
        swarmFingerprint = "ABCD-EFGH-IJKL"
    }

    -- Pocket sends full credentials
    withEnv(pocketEnv, function()
        rednet.open("back")
        local deliver = Protocol.createPairDeliver(fullCredentials.swarmSecret, fullCredentials.zoneId)
        deliver.data.credentials = fullCredentials
        local signed = Crypto.wrapWith(deliver, displayCode)
        rednet.send(zoneId, signed, Pairing.PROTOCOL)
    end)

    -- Zone extracts credentials (matching Pairing.lua logic)
    local extractedCreds = nil
    withEnv(zoneEnv, function()
        rednet.open("top")
        local _, envelope = network:receive(zoneId, Pairing.PROTOCOL)
        local unwrapped = Crypto.unwrapWith(envelope, displayCode)

        if unwrapped and unwrapped.data then
            -- Match Pairing.lua extraction logic
            local creds = unwrapped.data.credentials
            if creds then
                extractedCreds = {
                    swarmSecret = creds.swarmSecret,
                    zoneId = creds.zoneId,
                    fingerprint = creds.swarmFingerprint
                }
            else
                extractedCreds = {
                    swarmSecret = unwrapped.data.secret,
                    zoneId = unwrapped.data.zoneId
                }
            end
        end
    end)

    assert_not_nil(extractedCreds, "Should extract credentials")
    assert_eq(fullCredentials.swarmSecret, extractedCreds.swarmSecret)
    assert_eq(fullCredentials.zoneId, extractedCreds.zoneId)
    assert_eq(fullCredentials.swarmFingerprint, extractedCreds.fingerprint)
end)
