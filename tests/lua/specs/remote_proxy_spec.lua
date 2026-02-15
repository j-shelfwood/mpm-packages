-- remote_proxy_spec.lua
-- Tests for net/RemoteProxy.lua auto-reconnect logic

local root = _G.TEST_ROOT or "."
local module_cache = {}

_G.mpm = function(name)
    if not module_cache[name] then
        module_cache[name] = dofile(root .. "/" .. name .. ".lua")
    end
    return module_cache[name]
end

local RemoteProxy = mpm("net/RemoteProxy")
local Protocol = mpm("net/Protocol")

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

-- Create a mock client for testing
local function createMockClient(callResults)
    callResults = callResults or {}
    local client = {
        callLog = {},
        rediscoverLog = {},
        rediscoverResult = nil,
    }

    function client:call(hostId, peripheralName, methodName, args, timeout)
        local entry = {
            hostId = hostId,
            peripheral = peripheralName,
            method = methodName,
            args = args,
        }
        table.insert(self.callLog, entry)

        -- Return configured result or default error
        local result = callResults[methodName]
        if result then
            if result.err then
                return nil, result.err
            end
            return result.data, nil
        end

        return {42}, nil  -- Default success
    end

    function client:rediscover(name)
        table.insert(self.rediscoverLog, name)
        return self.rediscoverResult
    end

    return client
end

-- ============================================================================
-- Tests
-- ============================================================================

test("RemoteProxy.create returns proxy with correct metadata", function()
    local client = createMockClient()
    local proxy = RemoteProxy.create(client, 10, "me_bridge_0", "me_bridge", {"getItems", "getFluids"})

    assert_eq("me_bridge", proxy.getType())
    assert_eq("me_bridge_0", proxy.getName())
    assert_true(proxy.isConnected())
    assert_true(proxy._isRemote)
    assert_eq(10, proxy._hostId)

    local methods = proxy.getMethods()
    assert_eq(2, #methods)
end)

test("RemoteProxy method call forwards to client:call() correctly", function()
    local client = createMockClient({
        getItems = { data = {{name = "minecraft:diamond", amount = 256}} }
    })
    local proxy = RemoteProxy.create(client, 10, "me_bridge_0", "me_bridge", {"getItems"})

    local result = proxy.getItems()

    assert_eq(1, #client.callLog)
    assert_eq(10, client.callLog[1].hostId)
    assert_eq("me_bridge_0", client.callLog[1].peripheral)
    assert_eq("getItems", client.callLog[1].method)
    -- Result is unpacked from results array
    assert_true(result ~= nil)
end)

test("RemoteProxy single failure increments counter but stays connected", function()
    local client = createMockClient({
        getItems = { err = "timeout" }
    })
    local proxy = RemoteProxy.create(client, 10, "me_bridge_0", "me_bridge", {"getItems"})

    local result = proxy.getItems()

    assert_nil(result, "Should return nil on error")
    assert_true(proxy.isConnected(), "Should still be connected after 1 failure")
    assert_eq(1, proxy._failureCount)
end)

test("RemoteProxy disconnects after MAX_CONSECUTIVE_FAILURES (3)", function()
    local client = createMockClient({
        getItems = { err = "timeout" }
    })
    local proxy = RemoteProxy.create(client, 10, "me_bridge_0", "me_bridge", {"getItems"})

    -- First 2 failures: still connected
    proxy.getItems()
    proxy.getItems()
    assert_true(proxy.isConnected(), "Should be connected after 2 failures")
    assert_eq(2, proxy._failureCount)

    -- Third failure: disconnects
    proxy.getItems()
    assert_false(proxy.isConnected(), "Should disconnect after 3 failures")
    assert_eq(3, proxy._failureCount)
end)

test("RemoteProxy cooldown prevents rapid reconnect attempts", function()
    local now = 1000000
    local originalEpoch = os.epoch
    os.epoch = function() return now end

    local client = createMockClient({
        getItems = { err = "timeout" }
    })
    local proxy = RemoteProxy.create(client, 10, "me_bridge_0", "me_bridge", {"getItems"})

    -- Trigger disconnect
    proxy.getItems()
    proxy.getItems()
    proxy.getItems()
    assert_false(proxy.isConnected())

    -- Try calling again immediately (within cooldown) - should not attempt rediscover
    local result = proxy.getItems()
    assert_nil(result)
    assert_eq(0, #client.rediscoverLog, "Should not attempt rediscover within cooldown")

    os.epoch = originalEpoch
end)

test("RemoteProxy ensureConnected calls rediscover after cooldown", function()
    local now = 1000000
    local originalEpoch = os.epoch
    os.epoch = function() return now end

    local client = createMockClient({
        getItems = { err = "timeout" }
    })
    client.rediscoverResult = { hostId = 20, type = "me_bridge", methods = {"getItems"} }

    local proxy = RemoteProxy.create(client, 10, "me_bridge_0", "me_bridge", {"getItems"})

    -- Trigger disconnect
    proxy.getItems()
    proxy.getItems()
    proxy.getItems()
    assert_false(proxy.isConnected())

    -- Advance past cooldown (10000ms)
    now = now + 11000

    -- Switch to success responses for after reconnect
    client.call = function(self, hostId, peripheralName, methodName, args)
        return {99}, nil
    end

    -- Next call should trigger rediscover and succeed
    local result = proxy.getItems()
    assert_eq(1, #client.rediscoverLog, "Should attempt rediscover after cooldown")
    assert_true(proxy.isConnected(), "Should be reconnected")
    assert_eq(20, proxy._hostId, "Host ID should update after rediscover")

    os.epoch = originalEpoch
end)

test("RemoteProxy successful call resets failure counter", function()
    local callCount = 0
    local client = createMockClient()
    -- Override call to alternate between failure and success
    client.call = function(self, hostId, peripheralName, methodName, args)
        callCount = callCount + 1
        if callCount <= 2 then
            return nil, "timeout"
        end
        return {42}, nil
    end

    local proxy = RemoteProxy.create(client, 10, "me_bridge_0", "me_bridge", {"getItems"})

    -- Two failures
    proxy.getItems()
    proxy.getItems()
    assert_eq(2, proxy._failureCount)

    -- Success resets counter
    proxy.getItems()
    assert_eq(0, proxy._failureCount)
    assert_true(proxy.isConnected())
end)

test("RemoteProxy.reconnect() force-reconnects ignoring cooldown", function()
    local now = 1000000
    local originalEpoch = os.epoch
    os.epoch = function() return now end

    local client = createMockClient({
        getItems = { err = "timeout" }
    })
    client.rediscoverResult = { hostId = 30, type = "me_bridge", methods = {"getItems"} }

    local proxy = RemoteProxy.create(client, 10, "me_bridge_0", "me_bridge", {"getItems"})

    -- Trigger disconnect
    proxy.getItems()
    proxy.getItems()
    proxy.getItems()
    assert_false(proxy.isConnected())

    -- Force reconnect WITHOUT advancing time (still within cooldown)
    local success = proxy.reconnect()
    assert_true(success, "Force reconnect should succeed")
    assert_true(proxy.isConnected())
    assert_eq(30, proxy._hostId)
    assert_eq(0, proxy._failureCount)

    os.epoch = originalEpoch
end)

test("RemoteProxy.isProxy identifies proxy objects", function()
    local client = createMockClient()
    local proxy = RemoteProxy.create(client, 10, "me_bridge_0", "me_bridge", {"getItems"})

    assert_true(RemoteProxy.isProxy(proxy))
    assert_false(RemoteProxy.isProxy({}))
    assert_false(RemoteProxy.isProxy("string"))
    assert_false(RemoteProxy.isProxy(nil))
end)

test("RemoteProxy returns nil when disconnected and cooldown not elapsed", function()
    local now = 1000000
    local originalEpoch = os.epoch
    os.epoch = function() return now end

    local client = createMockClient({
        getItems = { err = "timeout" }
    })

    local proxy = RemoteProxy.create(client, 10, "me_bridge_0", "me_bridge", {"getItems", "getFluids"})

    -- Trigger disconnect via getItems
    proxy.getItems()
    proxy.getItems()
    proxy.getItems()
    assert_false(proxy.isConnected())

    -- getFluids should also return nil (same proxy, disconnected)
    local result = proxy.getFluids()
    assert_nil(result, "All methods should return nil when disconnected")

    os.epoch = originalEpoch
end)
