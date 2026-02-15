-- rpc_roundtrip_spec.lua
-- Full RPC roundtrip integration tests:
-- PeripheralHost ↔ PeripheralClient → RemoteProxy → AEInterface
-- Tests the exact data flow that was broken by the empty-remote-items bug

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
local PeripheralClient = mpm("net/PeripheralClient")
local RemoteProxy = mpm("net/RemoteProxy")
local AEInterface = mpm("peripherals/AEInterface")

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

-- Create linked channels that route messages between host and client in-process
-- This bypasses rednet/crypto and tests the handler logic directly
local function createLinkedChannels()
    local hostChannel = { handlers = {}, sendLog = {}, broadcastLog = {} }
    local clientChannel = { handlers = {}, sendLog = {}, broadcastLog = {} }

    -- Host sends → delivered to client handlers
    function hostChannel:send(targetId, msg)
        table.insert(self.sendLog, { targetId = targetId, msg = msg })
        local handler = clientChannel.handlers[msg.type]
        if handler then
            handler(10, msg)  -- 10 = host computer ID
        end
    end

    function hostChannel:broadcast(msg)
        table.insert(self.broadcastLog, msg)
        local handler = clientChannel.handlers[msg.type]
        if handler then
            handler(10, msg)
        end
    end

    function hostChannel:on(msgType, handler)
        self.handlers[msgType] = handler
    end

    function hostChannel:poll(timeout) end

    -- Client sends → delivered to host handlers
    function clientChannel:send(targetId, msg)
        table.insert(self.sendLog, { targetId = targetId, msg = msg })
        local handler = hostChannel.handlers[msg.type]
        if handler then
            handler(20, msg)  -- 20 = client computer ID
        end
    end

    function clientChannel:broadcast(msg)
        table.insert(self.broadcastLog, msg)
        local handler = hostChannel.handlers[msg.type]
        if handler then
            handler(20, msg)
        end
    end

    function clientChannel:on(msgType, handler)
        self.handlers[msgType] = handler
    end

    function clientChannel:poll(timeout) end

    return hostChannel, clientChannel
end

-- ============================================================================
-- Tests
-- ============================================================================

test("RPC roundtrip: host responds to PERIPH_DISCOVER with me_bridge in PERIPH_LIST", function()
    Mocks.setupComputer({ meBridge = true })

    local hostChannel, clientChannel = createLinkedChannels()

    -- Setup host side
    local host = PeripheralHost.new(hostChannel, 10, "HostComputer")
    host:scan()
    host:registerHandlers()

    -- Setup client side
    local client = PeripheralClient.new(clientChannel)
    client:registerHandlers()

    -- Client sends PERIPH_DISCOVER → host auto-responds via linked channels
    local discoverMsg = Protocol.createPeriphDiscover()
    clientChannel:broadcast(discoverMsg)

    -- Client should now have registered the me_bridge
    assert_true(client:getCount() >= 1, "Client should have registered peripherals")
    local proxy = client:find("me_bridge")
    assert_true(proxy ~= nil, "Client should find me_bridge proxy")
    assert_eq("me_bridge", proxy.getType())
end)

test("RPC roundtrip: client registers me_bridge proxy from PERIPH_ANNOUNCE", function()
    Mocks.setupComputer({ meBridge = true })

    local hostChannel, clientChannel = createLinkedChannels()

    local host = PeripheralHost.new(hostChannel, 10, "HostComputer")
    host:scan()
    host:registerHandlers()

    local client = PeripheralClient.new(clientChannel)
    client:registerHandlers()

    -- Host announces → delivered to client
    host:announce()

    assert_true(client:getCount() >= 1)
    local proxy = client:find("me_bridge")
    assert_true(proxy ~= nil)
    assert_true(RemoteProxy.isProxy(proxy))
end)

test("RPC roundtrip: full item data flow from ME Bridge mock → Host → Client → Proxy", function()
    Mocks.setupComputer({ meBridge = true })

    local hostChannel, clientChannel = createLinkedChannels()

    -- Setup host
    local host = PeripheralHost.new(hostChannel, 10, "HostComputer")
    host:scan()
    host:registerHandlers()

    -- Setup client with handlers
    local client = PeripheralClient.new(clientChannel)
    client:registerHandlers()

    -- Register peripherals via announce
    host:announce()

    -- Now manually test the call flow:
    -- 1. Create PERIPH_CALL for getItems
    local callMsg = Protocol.createPeriphCall("me_bridge_0", "getItems", {})

    -- 2. Store pending request on client
    local receivedResults = nil
    local receivedError = nil
    client.pendingRequests[callMsg.requestId] = {
        callback = function(results, err)
            receivedResults = results
            receivedError = err
        end
    }

    -- 3. Send call from client to host (via linked channels)
    clientChannel:send(10, callMsg)

    -- 4. The linked channel auto-routes:
    --    client:send → hostChannel handler (PERIPH_CALL) → host:handleCall
    --    → host sends PERIPH_RESULT → clientChannel handler (PERIPH_RESULT) → client:handleResult
    --    → resolves pending request callback

    assert_nil(receivedError, "Should have no error")
    assert_true(receivedResults ~= nil, "Should have results")

    -- Results should contain the ME Bridge mock's item data (5 default items)
    -- Results from pcall are packed as an array of return values
    -- First return value is the items array
    assert_true(#receivedResults >= 1, "Should have at least one return value")
    local items = receivedResults[1]
    assert_true(type(items) == "table", "First result should be items table")
    assert_true(#items >= 1, "Should have at least one item")

    -- Verify item structure matches ME Bridge mock
    local foundDiamond = false
    for _, item in ipairs(items) do
        if item.name == "minecraft:diamond" then
            foundDiamond = true
            assert_eq(256, item.amount)
            assert_eq("Diamond", item.displayName)
        end
    end
    assert_true(foundDiamond, "Should contain diamond from ME Bridge mock")
end)

test("RPC roundtrip: full fluid data flow", function()
    Mocks.setupComputer({ meBridge = true })

    local hostChannel, clientChannel = createLinkedChannels()

    local host = PeripheralHost.new(hostChannel, 10, "HostComputer")
    host:scan()
    host:registerHandlers()

    local client = PeripheralClient.new(clientChannel)
    client:registerHandlers()
    host:announce()

    -- Call getFluids
    local callMsg = Protocol.createPeriphCall("me_bridge_0", "getFluids", {})
    local receivedResults = nil
    client.pendingRequests[callMsg.requestId] = {
        callback = function(results, err) receivedResults = results end
    }
    clientChannel:send(10, callMsg)

    assert_true(receivedResults ~= nil, "Should have fluid results")
    local fluids = receivedResults[1]
    assert_true(type(fluids) == "table")
    assert_true(#fluids >= 1)

    local foundWater = false
    for _, fluid in ipairs(fluids) do
        if fluid.name == "minecraft:water" then
            foundWater = true
            assert_eq(64000, fluid.amount)
        end
    end
    assert_true(foundWater, "Should contain water from ME Bridge mock")
end)

test("RPC roundtrip: energy stats flow correctly", function()
    Mocks.setupComputer({ meBridge = true })

    local hostChannel, clientChannel = createLinkedChannels()

    local host = PeripheralHost.new(hostChannel, 10, "HostComputer")
    host:scan()
    host:registerHandlers()

    local client = PeripheralClient.new(clientChannel)
    client:registerHandlers()
    host:announce()

    -- Call getStoredEnergy
    local callMsg = Protocol.createPeriphCall("me_bridge_0", "getStoredEnergy", {})
    local receivedResults = nil
    client.pendingRequests[callMsg.requestId] = {
        callback = function(results, err) receivedResults = results end
    }
    clientChannel:send(10, callMsg)

    assert_true(receivedResults ~= nil, "Should have energy results")
    assert_eq(500000, receivedResults[1], "Should return stored energy value from mock")
end)

test("RPC roundtrip: host returns PERIPH_ERROR for missing peripheral", function()
    Mocks.setupComputer({ meBridge = true })

    local hostChannel, clientChannel = createLinkedChannels()

    local host = PeripheralHost.new(hostChannel, 10, "HostComputer")
    host:scan()
    host:registerHandlers()

    local client = PeripheralClient.new(clientChannel)
    client:registerHandlers()

    -- Call a non-existent peripheral
    local callMsg = Protocol.createPeriphCall("nonexistent_0", "getItems", {})
    local receivedResults = nil
    local receivedError = nil
    client.pendingRequests[callMsg.requestId] = {
        callback = function(results, err)
            receivedResults = results
            receivedError = err
        end
    }
    clientChannel:send(10, callMsg)

    assert_nil(receivedResults, "Should have no results on error")
    assert_true(receivedError ~= nil, "Should have error")
    assert_true(receivedError:find("not found"), "Error should indicate peripheral not found")
end)

test("RPC roundtrip: AEInterface works with RemoteProxy end-to-end", function()
    -- Setup host side with ME Bridge
    Mocks.setupComputer({ meBridge = true })

    local hostChannel, clientChannel = createLinkedChannels()

    local host = PeripheralHost.new(hostChannel, 10, "HostComputer")
    host:scan()
    host:registerHandlers()

    local client = PeripheralClient.new(clientChannel)
    client:registerHandlers()
    host:announce()

    -- Get the proxy
    local proxy = client:find("me_bridge")
    assert_true(proxy ~= nil, "Should have me_bridge proxy")

    -- Override client:call to be synchronous for this test
    -- (normally it uses polling loop with Yield.yield, but we bypass that)
    local origCall = client.call
    client.call = function(self, hostId, peripheralName, methodName, args, timeout)
        -- Create call message
        local msg = Protocol.createPeriphCall(peripheralName, methodName, args or {})

        -- Set up synchronous result capture
        local result = nil
        local err = nil
        self.pendingRequests[msg.requestId] = {
            callback = function(r, e)
                result = r
                err = e
            end
        }

        -- Send (linked channel will synchronously deliver and resolve)
        clientChannel:send(hostId, msg)

        return result, err
    end

    -- Create AEInterface with the proxy
    local ae = AEInterface.new(proxy)
    assert_true(ae ~= nil, "Should create AEInterface from proxy")
    assert_true(ae.isRemote, "Should detect as remote")

    -- Test items()
    local items = ae:items()
    assert_true(items ~= nil, "Should return items")
    assert_true(#items >= 1, "Should have items")

    -- Find diamond
    local foundDiamond = false
    for _, item in ipairs(items) do
        if item.registryName == "minecraft:diamond" then
            foundDiamond = true
            assert_eq("Diamond", item.displayName)
            assert_eq(256, item.count)
        end
    end
    assert_true(foundDiamond, "AEInterface should normalize and return diamond")

    -- Test energy()
    local energy = ae:energy()
    assert_eq(500000, energy.stored)
    assert_eq(1000000, energy.capacity)

    -- Restore
    client.call = origCall
end)

test("RPC roundtrip: multiple peripherals from single host", function()
    Mocks.reset()
    Mocks.install()

    -- Attach ME Bridge and a second peripheral
    local MEBridge = Mocks.MEBridge
    local meBridge = MEBridge.new()
    Mocks.Peripheral.attach("me_bridge_0", "me_bridge", meBridge)

    -- Add a chatBox mock
    local chatBox = {
        sendMessage = function(msg) return true end,
        getLabel = function() return "ChatBox" end,
    }
    Mocks.Peripheral.attach("chatBox_0", "chatBox", chatBox)

    -- Attach modem (excluded from sharing)
    local Modem = Mocks.Modem
    local modem = Modem.new({ name = "top", wireless = true })
    Mocks.Peripheral.attach("top", "modem", modem)

    local hostChannel, clientChannel = createLinkedChannels()

    local host = PeripheralHost.new(hostChannel, 10, "HostComputer")
    host:scan()
    host:registerHandlers()

    local client = PeripheralClient.new(clientChannel)
    client:registerHandlers()
    host:announce()

    -- Should have me_bridge and chatBox but NOT modem
    assert_eq(2, client:getCount(), "Should have 2 shared peripherals (me_bridge + chatBox)")

    local meBridgeProxy = client:find("me_bridge")
    assert_true(meBridgeProxy ~= nil)

    local chatBoxProxy = client:find("chatBox")
    assert_true(chatBoxProxy ~= nil)

    -- Modem should not be shared
    local modemProxy = client:find("modem")
    assert_nil(modemProxy, "Modem should not be shared")
end)

test("RPC roundtrip: rescan picks up newly attached peripherals", function()
    Mocks.setupComputer({ meBridge = true })

    local hostChannel, clientChannel = createLinkedChannels()

    local host = PeripheralHost.new(hostChannel, 10, "HostComputer")
    host:scan()
    host:registerHandlers()

    local client = PeripheralClient.new(clientChannel)
    client:registerHandlers()

    -- Initial announce
    host:announce()
    local initialCount = client:getCount()

    -- Attach new peripheral
    local chatBox = {
        sendMessage = function(msg) return true end,
    }
    Mocks.Peripheral.attach("chatBox_0", "chatBox", chatBox)

    -- Rescan and re-announce
    host:rescan()

    -- Client should have more peripherals now
    assert_true(client:getCount() > initialCount, "Should discover newly attached peripheral")
end)
