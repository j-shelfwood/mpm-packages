-- Swarm Simulation Test
-- Simulates a complete pairing flow between pocket and zone computers
-- Uses parallel coroutines to simulate concurrent execution

local WORKSPACE = "/workspace"

-- Setup mpm loader
local module_cache = {}
_G.mpm = function(name)
    if not module_cache[name] then
        local path = WORKSPACE .. "/" .. name .. ".lua"
        if not fs.exists(path) then
            error("Module not found: " .. name)
        end
        module_cache[name] = dofile(path)
    end
    return module_cache[name]
end

-- Load modules
local Protocol = mpm("net/Protocol")
local Crypto = mpm("net/Crypto")
local Pairing = mpm("net/Pairing")

-- Test state
local testResults = {
    passed = 0,
    failed = 0,
    errors = {}
}

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        testResults.passed = testResults.passed + 1
        print("[PASS] " .. name)
    else
        testResults.failed = testResults.failed + 1
        table.insert(testResults.errors, { name = name, error = err })
        print("[FAIL] " .. name)
        print("       " .. tostring(err))
    end
end

local function assert_true(v, msg) if not v then error(msg or "Expected true") end end
local function assert_eq(e, a, msg)
    if e ~= a then error((msg or "Values differ") .. string.format(" (expected=%s, actual=%s)", tostring(e), tostring(a))) end
end
local function assert_not_nil(v, msg) if v == nil then error(msg or "Expected non-nil") end end

-- =============================================================================
-- SIMULATED NETWORK
-- =============================================================================

-- In-memory message bus for simulating rednet without actual modems
-- Broadcasts are stored globally and each receiver tracks what they've seen
local MessageBus = {
    directMessages = {},    -- targetId -> {messages}
    broadcasts = {},        -- {sender, message, protocol, deliveredTo = {}}
}

function MessageBus.reset()
    MessageBus.directMessages = {}
    MessageBus.broadcasts = {}
end

function MessageBus.send(from, to, message, protocol)
    local key = tostring(to)
    MessageBus.directMessages[key] = MessageBus.directMessages[key] or {}
    table.insert(MessageBus.directMessages[key], {
        sender = from,
        message = message,
        protocol = protocol
    })
end

function MessageBus.broadcast(from, message, protocol)
    -- Store broadcast with delivery tracking
    -- Any computer can receive this until they mark it delivered
    table.insert(MessageBus.broadcasts, {
        sender = from,
        message = message,
        protocol = protocol,
        deliveredTo = {}  -- Track which computers have received this
    })
end

function MessageBus.receive(computerId, protocol, timeout)
    local key = tostring(computerId)
    MessageBus.directMessages[key] = MessageBus.directMessages[key] or {}

    local deadline = os.clock() + (timeout or 0.5)
    while os.clock() < deadline do
        -- Check direct messages first
        for i, msg in ipairs(MessageBus.directMessages[key]) do
            if not protocol or msg.protocol == protocol then
                table.remove(MessageBus.directMessages[key], i)
                return msg.sender, msg.message, msg.protocol
            end
        end

        -- Check broadcasts not yet delivered to this computer
        for _, msg in ipairs(MessageBus.broadcasts) do
            if msg.sender ~= computerId and
               (not protocol or msg.protocol == protocol) and
               not msg.deliveredTo[computerId] then
                -- Mark as delivered to this computer
                msg.deliveredTo[computerId] = true
                return msg.sender, msg.message, msg.protocol
            end
        end

        -- Yield to allow other coroutines
        coroutine.yield()
    end
    return nil
end

-- =============================================================================
-- SIMULATED COMPUTERS
-- =============================================================================

local function createZoneComputer(id, name, displayCode, swarmSecret)
    return {
        id = id,
        name = name,
        displayCode = displayCode,
        receivedSecret = nil,
        receivedZoneId = nil,
        state = "idle",

        run = function(self)
            self.state = "broadcasting"

            -- Create PAIR_READY
            local ready = Protocol.createPairReady(nil, self.name, self.id)

            -- Broadcast PAIR_READY
            MessageBus.broadcast(self.id, ready, Pairing.PROTOCOL)

            self.state = "waiting"

            -- Wait for PAIR_DELIVER (short timeout for simulation)
            local deadline = os.clock() + 0.5
            while os.clock() < deadline do
                local sender, envelope, protocol = MessageBus.receive(self.id, Pairing.PROTOCOL, 0.01)

                if envelope and envelope.v and envelope.s then
                    -- Signed envelope - try to verify with display code
                    local unwrapped, err = Crypto.unwrapWith(envelope, self.displayCode)

                    if unwrapped and unwrapped.type == Protocol.MessageType.PAIR_DELIVER then
                        -- Extract credentials
                        local creds = unwrapped.data and unwrapped.data.credentials
                        if creds then
                            self.receivedSecret = creds.swarmSecret
                            self.receivedZoneId = creds.zoneId
                        else
                            self.receivedSecret = unwrapped.data and unwrapped.data.secret
                            self.receivedZoneId = unwrapped.data and unwrapped.data.zoneId
                        end

                        -- Send PAIR_COMPLETE
                        local complete = Protocol.createPairComplete(self.name)
                        MessageBus.send(self.id, sender, complete, Pairing.PROTOCOL)

                        self.state = "paired"
                        return true
                    end
                end

                coroutine.yield()
            end

            self.state = "timeout"
            return false
        end
    }
end

local function createPocketComputer(id, swarmSecret)
    return {
        id = id,
        swarmSecret = swarmSecret,
        discoveredZones = {},
        pairedZone = nil,
        state = "idle",

        run = function(self, targetZoneId, displayCode)
            self.state = "discovering"

            -- Wait for PAIR_READY from zones
            local deadline = os.clock() + 0.2
            while os.clock() < deadline do
                local sender, message, protocol = MessageBus.receive(self.id, Pairing.PROTOCOL, 0.01)

                if message and message.type == Protocol.MessageType.PAIR_READY then
                    self.discoveredZones[sender] = {
                        id = sender,
                        label = message.data.label,
                        computerId = message.data.computerId
                    }
                end

                coroutine.yield()
            end

            -- Find target zone
            local targetZone = self.discoveredZones[targetZoneId]
            if not targetZone then
                self.state = "zone_not_found"
                return false
            end

            self.state = "pairing"

            -- Create and sign PAIR_DELIVER
            local deliver = Protocol.createPairDeliver(self.swarmSecret, "zone_" .. targetZoneId)
            deliver.data.credentials = {
                swarmSecret = self.swarmSecret,
                zoneId = "zone_" .. targetZoneId,
                swarmFingerprint = "SIM-" .. self.id
            }
            local signedDeliver = Crypto.wrapWith(deliver, displayCode)

            -- Send to zone
            MessageBus.send(self.id, targetZoneId, signedDeliver, Pairing.PROTOCOL)

            -- Wait for PAIR_COMPLETE
            deadline = os.clock() + 0.3
            while os.clock() < deadline do
                local sender, message, protocol = MessageBus.receive(self.id, Pairing.PROTOCOL, 0.01)

                if sender == targetZoneId and message and message.type == Protocol.MessageType.PAIR_COMPLETE then
                    self.pairedZone = targetZone
                    self.state = "paired"
                    return true
                end

                coroutine.yield()
            end

            self.state = "timeout"
            return false
        end
    }
end

-- =============================================================================
-- TESTS
-- =============================================================================

term.clear()
term.setCursorPos(1, 1)
print("=== Swarm Simulation Tests ===")
print("")

test("Single zone-pocket pairing succeeds", function()
    MessageBus.reset()

    local displayCode = "ABCD-1234"
    local swarmSecret = Crypto.generateSecret()

    local zone = createZoneComputer(10, "Zone Alpha", displayCode, swarmSecret)
    local pocket = createPocketComputer(1, swarmSecret)

    -- Run both in parallel using coroutines
    local zoneRoutine = coroutine.create(function() return zone:run() end)
    local pocketRoutine = coroutine.create(function() return pocket:run(10, displayCode) end)

    local maxIterations = 500
    local iterations = 0

    while iterations < maxIterations do
        iterations = iterations + 1

        if coroutine.status(zoneRoutine) ~= "dead" then
            coroutine.resume(zoneRoutine)
        end

        if coroutine.status(pocketRoutine) ~= "dead" then
            coroutine.resume(pocketRoutine)
        end

        if coroutine.status(zoneRoutine) == "dead" and
           coroutine.status(pocketRoutine) == "dead" then
            break
        end

        sleep(0.001)
    end

    assert_eq("paired", zone.state, "Zone should be paired")
    assert_eq("paired", pocket.state, "Pocket should be paired")
    assert_eq(swarmSecret, zone.receivedSecret, "Zone should receive correct secret")
    assert_eq("zone_10", zone.receivedZoneId, "Zone should receive correct zoneId")
end)

test("Wrong display code fails pairing", function()
    MessageBus.reset()

    local correctCode = "REAL-CODE"
    local wrongCode = "FAKE-CODE"
    local swarmSecret = Crypto.generateSecret()

    local zone = createZoneComputer(20, "Zone Beta", correctCode, swarmSecret)
    local pocket = createPocketComputer(2, swarmSecret)

    local zoneRoutine = coroutine.create(function() return zone:run() end)
    local pocketRoutine = coroutine.create(function() return pocket:run(20, wrongCode) end)

    local maxIterations = 500
    local iterations = 0

    while iterations < maxIterations do
        iterations = iterations + 1

        if coroutine.status(zoneRoutine) ~= "dead" then
            coroutine.resume(zoneRoutine)
        end
        if coroutine.status(pocketRoutine) ~= "dead" then
            coroutine.resume(pocketRoutine)
        end

        if coroutine.status(zoneRoutine) == "dead" and
           coroutine.status(pocketRoutine) == "dead" then
            break
        end

        sleep(0.001)
    end

    -- Zone should timeout (wrong code signature fails)
    assert_eq("timeout", zone.state, "Zone should timeout with wrong code")
    assert_true(zone.receivedSecret == nil, "Zone should not receive secret")
end)

test("Multiple zones discovered by pocket", function()
    MessageBus.reset()

    local swarmSecret = Crypto.generateSecret()

    local zone1 = createZoneComputer(30, "Zone One", "CODE-0001", swarmSecret)
    local zone2 = createZoneComputer(31, "Zone Two", "CODE-0002", swarmSecret)
    local zone3 = createZoneComputer(32, "Zone Three", "CODE-0003", swarmSecret)
    local pocket = createPocketComputer(3, swarmSecret)

    -- Start all zones broadcasting
    local routines = {
        coroutine.create(function() return zone1:run() end),
        coroutine.create(function() return zone2:run() end),
        coroutine.create(function() return zone3:run() end),
    }

    -- Let zones broadcast
    for i = 1, 30 do
        for _, r in ipairs(routines) do
            if coroutine.status(r) ~= "dead" then
                coroutine.resume(r)
            end
        end
        sleep(0.001)
    end

    -- Pocket discovers zones (but doesn't pair)
    local pocketRoutine = coroutine.create(function()
        pocket.state = "discovering"
        local deadline = os.clock() + 0.1
        while os.clock() < deadline do
            local sender, message, protocol = MessageBus.receive(pocket.id, Pairing.PROTOCOL, 0.01)
            if message and message.type == Protocol.MessageType.PAIR_READY then
                pocket.discoveredZones[sender] = {
                    id = sender,
                    label = message.data.label
                }
            end
            coroutine.yield()
        end
        pocket.state = "discovered"
    end)

    for i = 1, 50 do
        if coroutine.status(pocketRoutine) ~= "dead" then
            coroutine.resume(pocketRoutine)
        else
            break
        end
        sleep(0.001)
    end

    -- Check discovery
    local count = 0
    for _ in pairs(pocket.discoveredZones) do count = count + 1 end

    assert_eq(3, count, "Pocket should discover 3 zones")
    assert_not_nil(pocket.discoveredZones[30], "Should find Zone One")
    assert_not_nil(pocket.discoveredZones[31], "Should find Zone Two")
    assert_not_nil(pocket.discoveredZones[32], "Should find Zone Three")
end)

test("Pocket pairs with second zone after selecting", function()
    MessageBus.reset()

    local swarmSecret = Crypto.generateSecret()
    local targetCode = "ZONE-TWO!"

    local zone1 = createZoneComputer(40, "Zone A", "ZONE-ONE!", swarmSecret)
    local zone2 = createZoneComputer(41, "Zone B", targetCode, swarmSecret)
    local pocket = createPocketComputer(4, swarmSecret)

    local routines = {
        coroutine.create(function() return zone1:run() end),
        coroutine.create(function() return zone2:run() end),
        coroutine.create(function() return pocket:run(41, targetCode) end),  -- Target zone 41
    }

    local maxIterations = 600  -- Zone 1 needs 0.5s timeout = 500+ iterations
    local iterations = 0

    while iterations < maxIterations do
        iterations = iterations + 1

        for _, r in ipairs(routines) do
            if coroutine.status(r) ~= "dead" then
                coroutine.resume(r)
            end
        end

        local allDead = true
        for _, r in ipairs(routines) do
            if coroutine.status(r) ~= "dead" then
                allDead = false
                break
            end
        end
        if allDead then break end

        sleep(0.001)
    end

    -- Zone 2 should be paired (correct code), Zone 1 should timeout
    assert_eq("timeout", zone1.state, "Zone 1 should timeout (not selected)")
    assert_eq("paired", zone2.state, "Zone 2 should be paired")
    assert_eq("paired", pocket.state, "Pocket should be paired")
    assert_eq(swarmSecret, zone2.receivedSecret, "Zone 2 should receive secret")
end)

test("Credential structure matches SwarmAuthority format", function()
    MessageBus.reset()

    local displayCode = "CRED-TEST"
    local swarmSecret = Crypto.generateSecret()

    local zone = createZoneComputer(50, "Cred Zone", displayCode, swarmSecret)
    local pocket = createPocketComputer(5, swarmSecret)

    local zoneRoutine = coroutine.create(function() return zone:run() end)
    local pocketRoutine = coroutine.create(function() return pocket:run(50, displayCode) end)

    local maxIterations = 500
    for i = 1, maxIterations do
        if coroutine.status(zoneRoutine) ~= "dead" then
            coroutine.resume(zoneRoutine)
        end
        if coroutine.status(pocketRoutine) ~= "dead" then
            coroutine.resume(pocketRoutine)
        end
        if coroutine.status(zoneRoutine) == "dead" and
           coroutine.status(pocketRoutine) == "dead" then
            break
        end
        sleep(0.001)
    end

    assert_eq("paired", zone.state)
    assert_eq(swarmSecret, zone.receivedSecret)
    assert_eq("zone_50", zone.receivedZoneId)
end)

-- =============================================================================
-- RESULTS
-- =============================================================================

print("")
print("=== Results ===")
print(string.format("Passed: %d, Failed: %d, Total: %d",
    testResults.passed, testResults.failed, testResults.passed + testResults.failed))

if testResults.failed > 0 then
    print("")
    print("Failures:")
    for _, e in ipairs(testResults.errors) do
        print("  - " .. e.name .. ": " .. tostring(e.error):sub(1, 60))
    end
    print("")
    print("TESTS FAILED")
else
    print("")
    print("ALL TESTS PASSED")
end

os.shutdown()
