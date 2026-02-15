-- peripheral_client_spec.lua
-- Tests for net/PeripheralClient.lua registration, discovery handling, and call mechanics

local root = _G.TEST_ROOT or "."
local module_cache = {}

_G.mpm = function(name)
    if not module_cache[name] then
        module_cache[name] = dofile(root .. "/" .. name .. ".lua")
    end
    return module_cache[name]
end

local Protocol = mpm("net/Protocol")
local PeripheralClient = mpm("net/PeripheralClient")
local RemoteProxy = mpm("net/RemoteProxy")

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

-- Create a mock channel for client testing
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

test("PeripheralClient.handleAnnounce() registers remote peripherals with proxies", function()
    local channel = createMockChannel()
    local client = PeripheralClient.new(channel)

    -- Simulate receiving a PERIPH_ANNOUNCE
    local announceMsg = Protocol.createPeriphAnnounce(10, "HostComputer", {
        { name = "me_bridge_0", type = "me_bridge", methods = {"getItems", "getFluids", "getStoredEnergy"} },
        { name = "chatBox_0", type = "chatBox", methods = {"sendMessage"} },
    })

    client:handleAnnounce(10, announceMsg)

    assert_eq(2, client:getCount(), "Should register 2 peripherals")

    -- Verify proxy was created
    local proxy = client:wrap("me_bridge_0")
    assert_true(proxy ~= nil, "Should be able to wrap me_bridge_0")
    assert_eq("me_bridge", proxy.getType())
    assert_eq("me_bridge_0", proxy.getName())
    assert_true(RemoteProxy.isProxy(proxy), "Should be a RemoteProxy")
end)

test("PeripheralClient.handlePeriphList() registers peripherals from discovery response", function()
    local channel = createMockChannel()
    local client = PeripheralClient.new(channel)

    -- Create a discovery request to get its requestId
    local discoverMsg = Protocol.createPeriphDiscover()

    -- Set up a pending request to verify callback resolution
    local callbackCalled = false
    client.pendingRequests[discoverMsg.requestId] = {
        callback = function(peripherals, err)
            callbackCalled = true
            assert_nil(err, "Should have no error")
            assert_eq(1, #peripherals)
        end
    }

    -- Simulate PERIPH_LIST response
    local listMsg = Protocol.createPeriphList(discoverMsg, {
        { name = "me_bridge_0", type = "me_bridge", methods = {"getItems"} },
    })

    client:handlePeriphList(10, listMsg)

    assert_eq(1, client:getCount())
    assert_true(callbackCalled, "Should resolve pending request callback")
end)

test("PeripheralClient.handleResult() resolves pending request callback", function()
    local channel = createMockChannel()
    local client = PeripheralClient.new(channel)

    local receivedResults = nil
    local receivedError = nil
    local requestId = Protocol.generateRequestId()

    client.pendingRequests[requestId] = {
        callback = function(results, err)
            receivedResults = results
            receivedError = err
        end
    }

    -- Simulate PERIPH_RESULT
    local resultMsg = Protocol.createMessage(Protocol.MessageType.PERIPH_RESULT, {
        results = {{name = "minecraft:diamond", amount = 256}}
    }, requestId)

    client:handleResult(10, resultMsg)

    assert_true(receivedResults ~= nil, "Should receive results")
    assert_nil(receivedError, "Should have no error")
    assert_nil(client.pendingRequests[requestId], "Pending request should be cleaned up")
end)

test("PeripheralClient.handleError() resolves pending request with error", function()
    local channel = createMockChannel()
    local client = PeripheralClient.new(channel)

    local receivedResults = nil
    local receivedError = nil
    local requestId = Protocol.generateRequestId()

    client.pendingRequests[requestId] = {
        callback = function(results, err)
            receivedResults = results
            receivedError = err
        end
    }

    -- Simulate PERIPH_ERROR
    local errorMsg = Protocol.createMessage(Protocol.MessageType.PERIPH_ERROR, {
        error = "Peripheral not found: missing_device"
    }, requestId)

    client:handleError(10, errorMsg)

    assert_nil(receivedResults, "Should have no results")
    assert_true(receivedError ~= nil, "Should receive error")
    assert_true(receivedError:find("not found"), "Error should contain 'not found'")
    assert_nil(client.pendingRequests[requestId], "Pending request should be cleaned up")
end)

test("PeripheralClient.find() returns proxy for matching type", function()
    local channel = createMockChannel()
    local client = PeripheralClient.new(channel)

    -- Register some peripherals
    client:registerRemote(10, "me_bridge_0", "me_bridge", {"getItems"})
    client:registerRemote(10, "chatBox_0", "chatBox", {"sendMessage"})

    local proxy = client:find("me_bridge")
    assert_true(proxy ~= nil)
    assert_eq("me_bridge", proxy.getType())

    local chatProxy = client:find("chatBox")
    assert_true(chatProxy ~= nil)
    assert_eq("chatBox", chatProxy.getType())

    local missing = client:find("nonexistent")
    assert_nil(missing)
end)

test("PeripheralClient.findAll() returns all proxies for matching type", function()
    local channel = createMockChannel()
    local client = PeripheralClient.new(channel)

    -- Register multiple ME bridges from different hosts
    client:registerRemote(10, "me_bridge_0", "me_bridge", {"getItems"})
    client:registerRemote(20, "me_bridge_1", "me_bridge", {"getItems"})
    client:registerRemote(10, "chatBox_0", "chatBox", {"sendMessage"})

    local bridges = client:findAll("me_bridge")
    assert_eq(2, #bridges, "Should find 2 me_bridge peripherals")

    local chatBoxes = client:findAll("chatBox")
    assert_eq(1, #chatBoxes)

    local empty = client:findAll("nonexistent")
    assert_eq(0, #empty)
end)

test("PeripheralClient.wrap() returns proxy by name", function()
    local channel = createMockChannel()
    local client = PeripheralClient.new(channel)

    client:registerRemote(10, "me_bridge_0", "me_bridge", {"getItems", "getFluids"})

    local proxy = client:wrap("me_bridge_0")
    assert_true(proxy ~= nil)
    assert_eq("me_bridge_0", proxy.getName())

    local missing = client:wrap("nonexistent")
    assert_nil(missing)
end)

test("PeripheralClient.getNames() returns all remote peripheral names", function()
    local channel = createMockChannel()
    local client = PeripheralClient.new(channel)

    client:registerRemote(10, "me_bridge_0", "me_bridge", {"getItems"})
    client:registerRemote(10, "chatBox_0", "chatBox", {"sendMessage"})
    client:registerRemote(20, "me_bridge_1", "me_bridge", {"getItems"})

    local names = client:getNames()
    assert_eq(3, #names)

    -- Verify all names present (order may vary)
    local nameSet = {}
    for _, n in ipairs(names) do nameSet[n] = true end
    assert_true(nameSet["me_bridge_0"])
    assert_true(nameSet["chatBox_0"])
    assert_true(nameSet["me_bridge_1"])
end)

test("PeripheralClient.getCount() returns correct count", function()
    local channel = createMockChannel()
    local client = PeripheralClient.new(channel)

    assert_eq(0, client:getCount())

    client:registerRemote(10, "me_bridge_0", "me_bridge", {"getItems"})
    assert_eq(1, client:getCount())

    client:registerRemote(10, "chatBox_0", "chatBox", {"sendMessage"})
    assert_eq(2, client:getCount())

    client:clear()
    assert_eq(0, client:getCount())
end)

test("PeripheralClient.registerHandlers() wires up all message handlers", function()
    local channel = createMockChannel()
    local client = PeripheralClient.new(channel)

    client:registerHandlers()

    assert_true(channel.handlers[Protocol.MessageType.PERIPH_ANNOUNCE] ~= nil, "Should register PERIPH_ANNOUNCE handler")
    assert_true(channel.handlers[Protocol.MessageType.PERIPH_LIST] ~= nil, "Should register PERIPH_LIST handler")
    assert_true(channel.handlers[Protocol.MessageType.PERIPH_RESULT] ~= nil, "Should register PERIPH_RESULT handler")
    assert_true(channel.handlers[Protocol.MessageType.PERIPH_ERROR] ~= nil, "Should register PERIPH_ERROR handler")
end)

test("PeripheralClient.handleAnnounce() stores host computer info", function()
    local channel = createMockChannel()
    local client = PeripheralClient.new(channel)

    local announceMsg = Protocol.createPeriphAnnounce(10, "HostComputer", {
        { name = "me_bridge_0", type = "me_bridge", methods = {"getItems"} },
    })

    client:handleAnnounce(10, announceMsg)

    assert_true(client.hostComputers[10] ~= nil, "Should store host computer info")
    assert_eq(10, client.hostComputers[10].computerId)
    assert_eq("HostComputer", client.hostComputers[10].computerName)
end)
