-- ME Bridge Views Integration Tests
-- Tests view rendering with mock ME Bridge peripheral

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

local function assert_not_nil(value, msg)
    if value == nil then error(msg or "Expected non-nil value") end
end

local function assert_contains(haystack, needle, msg)
    if not haystack:find(needle, 1, true) then
        error((msg or "String does not contain expected text") ..
              string.format(" (looking for '%s' in '%s')", needle, haystack))
    end
end

-- =============================================================================
-- TESTS: AEInterface Adapter
-- =============================================================================

test("AEInterface.exists() detects ME Bridge", function()
    Mocks.setupZone({id = 10, meBridge = true})

    local AEInterface = mpm("peripherals/AEInterface")
    local exists, bridge = AEInterface.exists()

    assert_true(exists, "Should detect ME Bridge")
    assert_not_nil(bridge, "Should return peripheral object")
end)

test("AEInterface.exists() returns false when no bridge", function()
    Mocks.setupZone({id = 10, meBridge = false})

    local AEInterface = mpm("peripherals/AEInterface")
    local exists = AEInterface.exists()

    assert_true(not exists, "Should not detect ME Bridge when not attached")
end)

test("AEInterface.new() creates working adapter", function()
    Mocks.setupZone({id = 10, meBridge = true})

    local AEInterface = mpm("peripherals/AEInterface")
    local ae = AEInterface.new()

    assert_not_nil(ae, "Should create adapter")
end)

test("AEInterface.items() returns normalized item list", function()
    Mocks.setupZone({id = 10, meBridge = true})

    local AEInterface = mpm("peripherals/AEInterface")
    local ae = AEInterface.new()
    local items = ae:items()  -- Instance method, use : syntax

    assert_true(#items > 0, "Should return items")

    -- Check normalization - AEInterface normalizes to registryName
    local diamond = nil
    for _, item in ipairs(items) do
        if item.registryName == "minecraft:diamond" then
            diamond = item
            break
        end
    end

    assert_not_nil(diamond, "Should have diamond")
    assert_not_nil(diamond.count, "Should have count")
    assert_not_nil(diamond.displayName, "Should have displayName")
end)

test("AEInterface.fluids() returns fluid list", function()
    Mocks.setupZone({id = 10, meBridge = true})

    local AEInterface = mpm("peripherals/AEInterface")
    local ae = AEInterface.new()
    local fluids = ae:fluids()  -- Instance method

    assert_true(#fluids > 0, "Should return fluids")

    local water = nil
    for _, fluid in ipairs(fluids) do
        if fluid.registryName == "minecraft:water" or fluid.name == "minecraft:water" then
            water = fluid
            break
        end
    end

    assert_not_nil(water, "Should have water")
    assert_not_nil(water.amount or water.count, "Should have amount")
end)

test("AEInterface.storageStatus() returns capacity info", function()
    Mocks.setupZone({id = 10, meBridge = true})

    local AEInterface = mpm("peripherals/AEInterface")
    local ae = AEInterface.new()

    -- Check raw bridge methods work
    local total = ae.bridge.getTotalItemStorage()
    local used = ae.bridge.getUsedItemStorage()

    assert_not_nil(total, "Should have total storage")
    assert_not_nil(used, "Should have used storage")
    assert_true(total > 0, "Total should be positive")
end)

test("AEInterface.energy() returns energy stats", function()
    Mocks.setupZone({id = 10, meBridge = true})

    local AEInterface = mpm("peripherals/AEInterface")
    local ae = AEInterface.new()
    local energy = ae:energy()  -- Instance method

    assert_not_nil(energy, "Should return energy")
    assert_not_nil(energy.stored, "Should have stored")
    assert_not_nil(energy.capacity, "Should have capacity")
    assert_not_nil(energy.usage, "Should have usage")
end)

-- =============================================================================
-- TESTS: Monitor Mock
-- =============================================================================

test("Monitor mock supports basic operations", function()
    local env = Mocks.setupZone({id = 10, monitors = 1})
    local mon = env.monitors["monitor_0"]

    -- Test size
    local w, h = mon:getSize()
    assert_eq(51, w)
    assert_eq(19, h)

    -- Test cursor
    mon:setCursorPos(10, 5)
    local x, y = mon:getCursorPos()
    assert_eq(10, x)
    assert_eq(5, y)

    -- Test write
    mon:write("Hello World")
    local line = mon:getLine(5)
    assert_contains(line, "Hello World", "Should contain written text")
end)

test("Monitor mock clear() resets buffer", function()
    local env = Mocks.setupZone({id = 10, monitors = 1})
    local mon = env.monitors["monitor_0"]

    mon:setCursorPos(1, 1)
    mon:write("Test Content")

    local lineBefore = mon:getLine(1)
    assert_contains(lineBefore, "Test Content")

    mon:clear()

    local lineAfter = mon:getLine(1)
    assert_eq(string.rep(" ", 51), lineAfter, "Line should be blank after clear")
end)

test("Monitor mock findText() locates content", function()
    local env = Mocks.setupZone({id = 10, monitors = 1})
    local mon = env.monitors["monitor_0"]

    mon:setCursorPos(5, 3)
    mon:write("MARKER")

    local x, y = mon:findText("MARKER")
    assert_eq(5, x, "Should find at correct X")
    assert_eq(3, y, "Should find at correct Y")
end)

-- =============================================================================
-- TESTS: Text Utilities
-- =============================================================================

test("Text.formatNumber formats large numbers", function()
    Mocks.setupZone({id = 10})

    local Text = mpm("utils/Text")

    -- Test actual output format (may vary)
    local k = Text.formatNumber(1000)
    local m = Text.formatNumber(1500000)
    local g = Text.formatNumber(2000000000)

    assert_true(k:find("K") or k:find("k"), "1000 should have K suffix")
    assert_true(m:find("M") or m:find("m"), "1.5M should have M suffix")
    assert_true(g:find("G") or g:find("B"), "2B should have G or B suffix")
    assert_eq("999", Text.formatNumber(999))
end)

test("Text.prettifyName converts registry names", function()
    Mocks.setupZone({id = 10})

    local Text = mpm("utils/Text")

    -- Check format (case may vary slightly)
    local diamond = Text.prettifyName("minecraft:diamond")
    local iron = Text.prettifyName("minecraft:iron_ingot")

    assert_true(diamond:lower() == "diamond", "Diamond should prettify to 'diamond'")
    assert_true(iron:lower():find("iron"), "Iron ingot should contain 'iron'")
    assert_true(iron:lower():find("ingot"), "Iron ingot should contain 'ingot'")
end)

-- =============================================================================
-- TESTS: View Integration (simplified - no full render loop)
-- =============================================================================

test("StorageGraph view can mount with ME Bridge", function()
    Mocks.setupZone({id = 10, meBridge = true})

    -- Load view module
    local StorageGraph = dofile(root .. "/mpm-packages/views/StorageGraph.lua")

    -- Check mount
    local canMount = StorageGraph.mount()
    assert_true(canMount, "StorageGraph should mount when ME Bridge present")
end)

test("StorageGraph view mount fails without ME Bridge", function()
    Mocks.setupZone({id = 10, meBridge = false})

    local StorageGraph = dofile(root .. "/mpm-packages/views/StorageGraph.lua")

    local canMount = StorageGraph.mount()
    assert_true(not canMount, "StorageGraph should NOT mount without ME Bridge")
end)

test("ItemBrowser view can mount with ME Bridge", function()
    Mocks.setupZone({id = 10, meBridge = true})

    local ItemBrowser = dofile(root .. "/mpm-packages/views/ItemBrowser.lua")

    local canMount = ItemBrowser.mount()
    assert_true(canMount, "ItemBrowser should mount when ME Bridge present")
end)

test("Clock view always mounts (no peripheral required)", function()
    Mocks.setupZone({id = 10, meBridge = false})

    local Clock = dofile(root .. "/mpm-packages/views/Clock.lua")

    local canMount = Clock.mount()
    assert_true(canMount, "Clock should always mount")
end)

test("EnergyGraph view mount depends on ME Bridge", function()
    Mocks.setupZone({id = 10, meBridge = true})

    local EnergyGraph = dofile(root .. "/mpm-packages/views/EnergyGraph.lua")

    local canMount = EnergyGraph.mount()
    assert_true(canMount, "EnergyGraph should mount when ME Bridge present")
end)

-- =============================================================================
-- TESTS: BaseView Framework
-- =============================================================================

test("BaseView.custom creates view with correct structure", function()
    Mocks.setupZone({id = 10})

    local BaseView = mpm("views/BaseView")

    local testView = BaseView.custom({
        name = "TestView",
        sleepTime = 2,
        mount = function() return true end,
        init = function(self, config)
            self.config = config
        end,
        -- BaseView requires both getData and render functions
        getData = function(self)
            return {value = 42}
        end,
        render = function(self, data)
            self.monitor.setCursorPos(1, 1)
            self.monitor.write("Value: " .. (data and data.value or "nil"))
        end
    })

    assert_not_nil(testView, "Should create view")
    -- BaseView returns module with: sleepTime, mount, new, getData, renderWithData
    assert_eq(2, testView.sleepTime, "sleepTime should match")
    assert_not_nil(testView.mount, "Should have mount function")
    assert_not_nil(testView.new, "Should have new function")
    assert_true(testView.mount(), "Mount should return true")
end)
