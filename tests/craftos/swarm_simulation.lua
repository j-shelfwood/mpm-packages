-- Swarm Simulation Test
-- Simulates a complete pairing flow between pocket and swarm computers
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

local function createSwarmComputer(id, name, displayCode, swarmSecret)
    return {
        id = id,
        name = name,
        displayCode = displayCode,
        receivedSecret = nil,
        receivedComputerId = nil,
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
                            self.receivedComputerId = creds.computerId
                        else
                            self.receivedSecret = unwrapped.data and unwrapped.data.secret
                            self.receivedComputerId = unwrapped.data and unwrapped.data.computerId
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
        discoveredComputers = {},
        pairedComputer = nil,
        state = "idle",

        run = function(self, targetComputerId, displayCode)
            self.state = "discovering"

            -- Wait for PAIR_READY from computers
            local deadline = os.clock() + 0.2
            while os.clock() < deadline do
                local sender, message, protocol = MessageBus.receive(self.id, Pairing.PROTOCOL, 0.01)

                if message and message.type == Protocol.MessageType.PAIR_READY then
                    self.discoveredComputers[sender] = {
                        id = sender,
                        label = message.data.label,
                        computerId = message.data.computerId
                    }
                end

                coroutine.yield()
            end

            -- Find target computer
            local targetComputer = self.discoveredComputers[targetComputerId]
            if not targetComputer then
                self.state = "computer_not_found"
                return false
            end

            self.state = "pairing"

            -- Create and sign PAIR_DELIVER
            local deliver = Protocol.createPairDeliver(self.swarmSecret, "computer_" .. targetComputerId)
            deliver.data.credentials = {
                swarmSecret = self.swarmSecret,
                computerId = "computer_" .. targetComputerId,
                swarmFingerprint = "SIM-" .. self.id
            }
            local signedDeliver = Crypto.wrapWith(deliver, displayCode)

            -- Send to target computer
            MessageBus.send(self.id, targetComputerId, signedDeliver, Pairing.PROTOCOL)

            -- Wait for PAIR_COMPLETE
            deadline = os.clock() + 0.3
            while os.clock() < deadline do
                local sender, message, protocol = MessageBus.receive(self.id, Pairing.PROTOCOL, 0.01)

                if sender == targetComputerId and message and message.type == Protocol.MessageType.PAIR_COMPLETE then
                    self.pairedComputer = targetComputer
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

test("Single computer-pocket pairing succeeds", function()
    MessageBus.reset()

    local displayCode = "ABCD-1234"
    local swarmSecret = Crypto.generateSecret()

    local comp = createSwarmComputer(10, "Computer Alpha", displayCode, swarmSecret)
    local pocket = createPocketComputer(1, swarmSecret)

    -- Run both in parallel using coroutines
    local compRoutine = coroutine.create(function() return comp:run() end)
    local pocketRoutine = coroutine.create(function() return pocket:run(10, displayCode) end)

    local maxIterations = 500
    local iterations = 0

    while iterations < maxIterations do
        iterations = iterations + 1

        if coroutine.status(compRoutine) ~= "dead" then
            coroutine.resume(compRoutine)
        end

        if coroutine.status(pocketRoutine) ~= "dead" then
            coroutine.resume(pocketRoutine)
        end

        if coroutine.status(compRoutine) == "dead" and
           coroutine.status(pocketRoutine) == "dead" then
            break
        end

        sleep(0.001)
    end

    assert_eq("paired", comp.state, "Computer should be paired")
    assert_eq("paired", pocket.state, "Pocket should be paired")
    assert_eq(swarmSecret, comp.receivedSecret, "Computer should receive correct secret")
    assert_eq("computer_10", comp.receivedComputerId, "Computer should receive correct computerId")
end)

test("Wrong display code fails pairing", function()
    MessageBus.reset()

    local correctCode = "REAL-CODE"
    local wrongCode = "FAKE-CODE"
    local swarmSecret = Crypto.generateSecret()

    local comp = createSwarmComputer(20, "Computer Beta", correctCode, swarmSecret)
    local pocket = createPocketComputer(2, swarmSecret)

    local compRoutine = coroutine.create(function() return comp:run() end)
    local pocketRoutine = coroutine.create(function() return pocket:run(20, wrongCode) end)

    local maxIterations = 500
    local iterations = 0

    while iterations < maxIterations do
        iterations = iterations + 1

        if coroutine.status(compRoutine) ~= "dead" then
            coroutine.resume(compRoutine)
        end
        if coroutine.status(pocketRoutine) ~= "dead" then
            coroutine.resume(pocketRoutine)
        end

        if coroutine.status(compRoutine) == "dead" and
           coroutine.status(pocketRoutine) == "dead" then
            break
        end

        sleep(0.001)
    end

    -- Computer should timeout (wrong code signature fails)
    assert_eq("timeout", comp.state, "Computer should timeout with wrong code")
    assert_true(comp.receivedSecret == nil, "Computer should not receive secret")
end)

test("Multiple computers discovered by pocket", function()
    MessageBus.reset()

    local swarmSecret = Crypto.generateSecret()

    local comp1 = createSwarmComputer(30, "Computer One", "CODE-0001", swarmSecret)
    local comp2 = createSwarmComputer(31, "Computer Two", "CODE-0002", swarmSecret)
    local comp3 = createSwarmComputer(32, "Computer Three", "CODE-0003", swarmSecret)
    local pocket = createPocketComputer(3, swarmSecret)

    -- Start all computers broadcasting
    local routines = {
        coroutine.create(function() return comp1:run() end),
        coroutine.create(function() return comp2:run() end),
        coroutine.create(function() return comp3:run() end),
    }

    -- Let computers broadcast
    for i = 1, 30 do
        for _, r in ipairs(routines) do
            if coroutine.status(r) ~= "dead" then
                coroutine.resume(r)
            end
        end
        sleep(0.001)
    end

    -- Pocket discovers computers (but doesn't pair)
    local pocketRoutine = coroutine.create(function()
        pocket.state = "discovering"
        local deadline = os.clock() + 0.1
        while os.clock() < deadline do
            local sender, message, protocol = MessageBus.receive(pocket.id, Pairing.PROTOCOL, 0.01)
            if message and message.type == Protocol.MessageType.PAIR_READY then
                pocket.discoveredComputers[sender] = {
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
    for _ in pairs(pocket.discoveredComputers) do count = count + 1 end

    assert_eq(3, count, "Pocket should discover 3 computers")
    assert_not_nil(pocket.discoveredComputers[30], "Should find Computer One")
    assert_not_nil(pocket.discoveredComputers[31], "Should find Computer Two")
    assert_not_nil(pocket.discoveredComputers[32], "Should find Computer Three")
end)

test("Pocket pairs with second computer after selecting", function()
    MessageBus.reset()

    local swarmSecret = Crypto.generateSecret()
    local targetCode = "COMP-TWO!"

    local comp1 = createSwarmComputer(40, "Computer A", "COMP-ONE!", swarmSecret)
    local comp2 = createSwarmComputer(41, "Computer B", targetCode, swarmSecret)
    local pocket = createPocketComputer(4, swarmSecret)

    local routines = {
        coroutine.create(function() return comp1:run() end),
        coroutine.create(function() return comp2:run() end),
        coroutine.create(function() return pocket:run(41, targetCode) end),  -- Target computer 41
    }

    local maxIterations = 600  -- Computer 1 needs 0.5s timeout = 500+ iterations
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

    -- Computer 2 should be paired (correct code), Computer 1 should timeout
    assert_eq("timeout", comp1.state, "Computer 1 should timeout (not selected)")
    assert_eq("paired", comp2.state, "Computer 2 should be paired")
    assert_eq("paired", pocket.state, "Pocket should be paired")
    assert_eq(swarmSecret, comp2.receivedSecret, "Computer 2 should receive secret")
end)

test("Credential structure matches SwarmAuthority format", function()
    MessageBus.reset()

    local displayCode = "CRED-TEST"
    local swarmSecret = Crypto.generateSecret()

    local comp = createSwarmComputer(50, "Cred Computer", displayCode, swarmSecret)
    local pocket = createPocketComputer(5, swarmSecret)

    local compRoutine = coroutine.create(function() return comp:run() end)
    local pocketRoutine = coroutine.create(function() return pocket:run(50, displayCode) end)

    local maxIterations = 500
    for i = 1, maxIterations do
        if coroutine.status(compRoutine) ~= "dead" then
            coroutine.resume(compRoutine)
        end
        if coroutine.status(pocketRoutine) ~= "dead" then
            coroutine.resume(pocketRoutine)
        end
        if coroutine.status(compRoutine) == "dead" and
           coroutine.status(pocketRoutine) == "dead" then
            break
        end
        sleep(0.001)
    end

    assert_eq("paired", comp.state)
    assert_eq(swarmSecret, comp.receivedSecret)
    assert_eq("computer_50", comp.receivedComputerId)
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
