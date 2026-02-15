-- view_lazy_init_spec.lua
-- Tests the lazy re-initialization pattern added to all views
-- Ensures views recover when peripheral becomes available after init failure

local root = _G.TEST_ROOT or "."
local module_cache = {}

-- Reload mpm modules fresh for each test pattern
local function resetModuleCache()
    module_cache = {}
end

_G.mpm = function(name)
    if not module_cache[name] then
        module_cache[name] = dofile(root .. "/" .. name .. ".lua")
    end
    return module_cache[name]
end

local Mocks = require("mocks")

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

local function assert_not_nil(value, message)
    if value == nil then error(message or "expected non-nil") end
end

-- Create a mock monitor object for view instantiation
local function createMockMonitor(width, height)
    width = width or 39
    height = height or 13
    return {
        getSize = function() return width, height end,
        setCursorPos = function() end,
        write = function() end,
        setTextColor = function() end,
        setBackgroundColor = function() end,
        clear = function() end,
        clearLine = function() end,
        blit = function() end,
        setTextScale = function() end,
        scroll = function() end,
        setVisible = function() end,
    }
end

-- ============================================================================
-- Tests: ListFactory lazy re-init
-- ============================================================================

test("ListFactory.getData() returns nil when AEInterface.new() fails (no peripheral)", function()
    -- Setup computer WITHOUT me_bridge
    Mocks.setupComputer({ meBridge = false })
    resetModuleCache()

    local ListFactory = mpm("views/factories/ListFactory")

    -- Create an ItemList-like view
    local viewDef = ListFactory.create({
        name = "Item",
        dataMethod = "items",
        amountField = "count",
    })

    -- Instantiate view
    local monitor = createMockMonitor()
    local instance = viewDef.new(monitor, {})

    -- getData should return nil (no me_bridge)
    local data = viewDef.getData(instance)
    assert_nil(data, "getData should return nil when no ME Bridge available")
end)

test("ListFactory.getData() retries AEInterface.new() on subsequent calls", function()
    -- Setup computer WITHOUT me_bridge
    Mocks.setupComputer({ meBridge = false })
    resetModuleCache()

    local ListFactory = mpm("views/factories/ListFactory")

    local viewDef = ListFactory.create({
        name = "Item",
        dataMethod = "items",
        amountField = "count",
    })

    local monitor = createMockMonitor()
    local instance = viewDef.new(monitor, {})

    -- First call: no peripheral, returns nil
    local data1 = viewDef.getData(instance)
    assert_nil(data1, "First getData should return nil")

    -- Verify interface is still nil on instance
    assert_nil(instance.interface, "Interface should be nil after failed init")

    -- Now attach ME Bridge
    local MEBridge = Mocks.MEBridge
    local meBridge = MEBridge.new()
    Mocks.Peripheral.attach("me_bridge_0", "me_bridge", meBridge)

    -- Second call: should retry and succeed
    local data2 = viewDef.getData(instance)
    assert_not_nil(data2, "Second getData should succeed after peripheral attached")
    assert_true(type(data2) == "table", "Should return table of items")
    assert_true(#data2 >= 1, "Should have items from ME Bridge")
end)

test("ListFactory.getData() succeeds when peripheral is available at init", function()
    -- Setup computer WITH me_bridge
    Mocks.setupComputer({ meBridge = true })
    resetModuleCache()

    local ListFactory = mpm("views/factories/ListFactory")

    local viewDef = ListFactory.create({
        name = "Item",
        dataMethod = "items",
        amountField = "count",
    })

    local monitor = createMockMonitor()
    local instance = viewDef.new(monitor, {})

    -- getData should work immediately
    local data = viewDef.getData(instance)
    assert_not_nil(data, "getData should return data when peripheral available")
    assert_true(#data >= 1, "Should have items")
end)

test("StorageGraph lazy re-init: returns nil then succeeds when peripheral appears", function()
    -- Setup computer WITHOUT me_bridge
    Mocks.setupComputer({ meBridge = false })
    resetModuleCache()

    -- Bootstrap stubs provide functional os.queueEvent/os.pullEventRaw
    -- so Yield.yield() works in synchronous tests

    local StorageGraph = mpm("views/StorageGraph")

    local monitor = createMockMonitor()
    local instance = StorageGraph.new(monitor, {})

    -- First call: no peripheral
    local data1 = StorageGraph.getData(instance)
    assert_nil(data1, "getData should return nil without ME Bridge")

    -- Attach ME Bridge
    local MEBridge = Mocks.MEBridge
    local meBridge = MEBridge.new()
    Mocks.Peripheral.attach("me_bridge_0", "me_bridge", meBridge)

    -- Second call: should succeed
    local data2 = StorageGraph.getData(instance)
    assert_not_nil(data2, "getData should succeed after peripheral attached")
    assert_true(data2.used ~= nil, "Should have used storage value")
    assert_true(data2.total ~= nil, "Should have total storage value")
end)

test("ListFactory fluid view lazy re-init works correctly", function()
    -- Setup computer WITHOUT me_bridge
    Mocks.setupComputer({ meBridge = false })
    resetModuleCache()

    local ListFactory = mpm("views/factories/ListFactory")

    -- Create a FluidList-like view
    local viewDef = ListFactory.create({
        name = "Fluid",
        dataMethod = "fluids",
        amountField = "amount",
        unitDivisor = 1000,
        unitLabel = "B",
    })

    local monitor = createMockMonitor()
    local instance = viewDef.new(monitor, {})

    -- First call: nil
    local data1 = viewDef.getData(instance)
    assert_nil(data1)

    -- Attach ME Bridge
    local MEBridge = Mocks.MEBridge
    local meBridge = MEBridge.new()
    Mocks.Peripheral.attach("me_bridge_0", "me_bridge", meBridge)

    -- Second call: should have fluids
    local data2 = viewDef.getData(instance)
    assert_not_nil(data2, "Should get fluid data after attach")
    assert_true(#data2 >= 1, "Should have fluids")

    -- Verify fluid data structure
    local foundWater = false
    for _, fluid in ipairs(data2) do
        if fluid.registryName == "minecraft:water" then
            foundWater = true
        end
    end
    assert_true(foundWater, "Should contain water from ME Bridge mock")
end)
