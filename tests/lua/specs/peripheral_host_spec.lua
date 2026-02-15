-- peripheral_host_spec.lua
-- Tests for net/PeripheralHost.lua peripheral scanning, filtering, and call handling

local root = _G.TEST_ROOT or "."
local module_cache = {}

_G.mpm = function(name)
    if not module_cache[name] then
        module_cache[name] = dofile(root .. "/" .. name .. ".lua")
    end
    return module_cache[name]
end

local Mocks = require("mocks")
local Protocol = mpm("net/Protocol")
local PeripheralHost = mpm("net/PeripheralHost")

local function assert_true(value, message)
    if not value then error(message or "expected true") end
end

local function assert_false(value, message)
    if value then error(message or "expected false") end
end

local function assert_eq(expected, actual, message)
    if expected ~= actual then
        error((message or "values differ") .. string.format(" (expected=%s actual=%s)", tostring(expected), tostring(actual)))
    end
end

local function assert_nil(value, message)
    if value ~= nil then
        error((message or "expected nil") .. string.format(" (got=%s)", tostring(value)))
    end
end

-- Create a mock channel that captures send/broadcast calls
local function createMockChannel()
    local channel = {
        sendLog = {},
        broadcastLog = {},
        handlers = {},
    }

    function channel:send(targetId, msg)
        table.insert(self.sendLog, { targetId = targetId, msg = msg })
    end

    function channel:broadcast(msg)
        table.insert(self.broadcastLog, msg)
    end

    function channel:on(msgType, handler)
        self.handlers[msgType] = handler
    end

    function channel:poll(timeout) end

    return channel
end

-- ============================================================================
-- Tests
-- ============================================================================

test("PeripheralHost.scan() discovers local peripherals", function()
    Mocks.setupComputer({ meBridge = true })

    local channel = createMockChannel()
    local host = PeripheralHost.new(channel, 10, "TestComputer")

    local count = host:scan()

    assert_true(count >= 1, "Should discover at least me_bridge")

    -- Verify me_bridge is in the list
    local list = host:getPeripheralList()
    local foundMeBridge = false
    for _, p in ipairs(list) do
        if p.type == "me_bridge" then
            foundMeBridge = true
            break
        end
    end
    assert_true(foundMeBridge, "Should discover me_bridge peripheral")
end)

test("PeripheralHost.scan() excludes monitors, modems, computers, turtles, pocket", function()
    Mocks.setupComputer({ meBridge = true, monitors = 2 })

    local channel = createMockChannel()
    local host = PeripheralHost.new(channel, 10, "TestComputer")
    host:scan()

    local list = host:getPeripheralList()

    for _, p in ipairs(list) do
        assert_true(p.type ~= "monitor", "Should not share monitors, found: " .. p.name)
        assert_true(p.type ~= "modem", "Should not share modems, found: " .. p.name)
        assert_true(p.type ~= "computer", "Should not share computers")
        assert_true(p.type ~= "turtle", "Should not share turtles")
        assert_true(p.type ~= "pocket", "Should not share pocket computers")
    end
end)

test("PeripheralHost.handleCall() executes peripheral method and returns result", function()
    Mocks.setupComputer({ meBridge = true })

    local channel = createMockChannel()
    local host = PeripheralHost.new(channel, 10, "TestComputer")
    host:scan()

    -- Create a PERIPH_CALL message for getItems
    local callMsg = Protocol.createPeriphCall("me_bridge_0", "getItems", {})
    local senderId = 20

    host:handleCall(senderId, callMsg)

    -- Should have sent a PERIPH_RESULT response
    assert_eq(1, #channel.sendLog, "Should send one response")
    assert_eq(20, channel.sendLog[1].targetId, "Should send to requester")

    local response = channel.sendLog[1].msg
    assert_eq(Protocol.MessageType.PERIPH_RESULT, response.type)
    assert_eq(callMsg.requestId, response.requestId, "Should preserve requestId")
    assert_true(response.data.results ~= nil, "Should have results")
end)

test("PeripheralHost.handleCall() returns PERIPH_ERROR for unknown peripheral", function()
    Mocks.setupComputer({ meBridge = true })

    local channel = createMockChannel()
    local host = PeripheralHost.new(channel, 10, "TestComputer")
    host:scan()

    local callMsg = Protocol.createPeriphCall("nonexistent_peripheral", "getItems", {})

    host:handleCall(20, callMsg)

    assert_eq(1, #channel.sendLog)
    local response = channel.sendLog[1].msg
    assert_eq(Protocol.MessageType.PERIPH_ERROR, response.type)
    assert_true(response.data.error:find("not found"), "Error should mention 'not found'")
end)

test("PeripheralHost.handleCall() returns PERIPH_ERROR for unknown method", function()
    Mocks.setupComputer({ meBridge = true })

    local channel = createMockChannel()
    local host = PeripheralHost.new(channel, 10, "TestComputer")
    host:scan()

    local callMsg = Protocol.createPeriphCall("me_bridge_0", "nonExistentMethod", {})

    host:handleCall(20, callMsg)

    assert_eq(1, #channel.sendLog)
    local response = channel.sendLog[1].msg
    assert_eq(Protocol.MessageType.PERIPH_ERROR, response.type)
    assert_true(response.data.error:find("not found"), "Error should mention 'not found'")
end)

test("PeripheralHost.handleCall() wraps pcall errors in PERIPH_ERROR", function()
    Mocks.reset()
    Mocks.install()

    -- Create a peripheral with a method that throws an error
    local badPeripheral = {
        explodingMethod = function()
            error("something went wrong!")
        end
    }
    Mocks.Peripheral.attach("bad_device_0", "bad_device", badPeripheral)

    local channel = createMockChannel()
    local host = PeripheralHost.new(channel, 10, "TestComputer")
    host:scan()

    local callMsg = Protocol.createPeriphCall("bad_device_0", "explodingMethod", {})

    host:handleCall(20, callMsg)

    assert_eq(1, #channel.sendLog)
    local response = channel.sendLog[1].msg
    assert_eq(Protocol.MessageType.PERIPH_ERROR, response.type)
    assert_true(response.data.error:find("something went wrong"), "Should contain error message")
end)

test("PeripheralHost.getPeripheralList() returns correct structure", function()
    Mocks.setupComputer({ meBridge = true })

    local channel = createMockChannel()
    local host = PeripheralHost.new(channel, 10, "TestComputer")
    host:scan()

    local list = host:getPeripheralList()
    assert_true(#list >= 1)

    -- Each entry should have name, type, methods
    for _, p in ipairs(list) do
        assert_true(p.name ~= nil, "Should have name")
        assert_true(p.type ~= nil, "Should have type")
        assert_true(p.methods ~= nil, "Should have methods")
        assert_true(type(p.methods) == "table", "Methods should be a table")
    end
end)

test("PeripheralHost.announce() broadcasts PERIPH_ANNOUNCE with peripheral list", function()
    Mocks.setupComputer({ meBridge = true })

    local channel = createMockChannel()
    local host = PeripheralHost.new(channel, 10, "TestComputer")
    host:scan()
    host:announce()

    assert_eq(1, #channel.broadcastLog, "Should broadcast once")
    local msg = channel.broadcastLog[1]
    assert_eq(Protocol.MessageType.PERIPH_ANNOUNCE, msg.type)
    assert_eq(10, msg.data.computerId)
    assert_eq("TestComputer", msg.data.computerName)
    assert_true(msg.data.peripherals ~= nil, "Should include peripheral list")
    assert_true(#msg.data.peripherals >= 1, "Should have at least one peripheral")
end)

test("PeripheralHost.handleDiscover() responds with PERIPH_LIST", function()
    Mocks.setupComputer({ meBridge = true })

    local channel = createMockChannel()
    local host = PeripheralHost.new(channel, 10, "TestComputer")
    host:scan()

    local discoverMsg = Protocol.createPeriphDiscover()

    host:handleDiscover(20, discoverMsg)

    assert_eq(1, #channel.sendLog)
    assert_eq(20, channel.sendLog[1].targetId)

    local response = channel.sendLog[1].msg
    assert_eq(Protocol.MessageType.PERIPH_LIST, response.type)
    assert_eq(discoverMsg.requestId, response.requestId, "Should correlate requestId")
    assert_true(response.data.peripherals ~= nil)
    assert_true(#response.data.peripherals >= 1)
end)

test("PeripheralHost.registerHandlers() wires up PERIPH_DISCOVER and PERIPH_CALL", function()
    Mocks.setupComputer({ meBridge = true })

    local channel = createMockChannel()
    local host = PeripheralHost.new(channel, 10, "TestComputer")
    host:registerHandlers()

    assert_true(channel.handlers[Protocol.MessageType.PERIPH_DISCOVER] ~= nil, "Should register PERIPH_DISCOVER handler")
    assert_true(channel.handlers[Protocol.MessageType.PERIPH_CALL] ~= nil, "Should register PERIPH_CALL handler")
end)
