-- Config Reconcile Integration Tests
-- Tests Config.discoverMonitors() deduplication and Config.reconcile() self-healing
-- Validates that boot-time config healing fixes duplicate monitors, remaps aliases,
-- and adds newly discovered monitors.

local root = _G.TEST_ROOT or "."

-- Setup module loader
local module_cache = {}
_G.mpm = function(name)
    if not module_cache[name] then
        module_cache[name] = dofile(root .. "/" .. name .. ".lua")
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

local function assert_false(value, msg)
    if value then error(msg or "Expected false") end
end

local function assert_nil(value, msg)
    if value ~= nil then error(msg or "Expected nil, got " .. tostring(value)) end
end

local function assert_not_nil(value, msg)
    if value == nil then error(msg or "Expected non-nil value") end
end

-- Helper: count items in a table (works for non-sequential keys)
local function tableCount(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- Helper: check if a value exists in an array
local function arrayContains(arr, value)
    for _, v in ipairs(arr) do
        if v == value then return true end
    end
    return false
end

-- Helper: install a mock ViewManager into module cache
-- Avoids loading real views/Manager which has heavy dependencies
local function installMockViewManager()
    module_cache["views/Manager"] = {
        suggestViewsForMonitors = function(count)
            local suggestions = {}
            local views = {"NetworkDashboard", "StorageGraph", "Clock", "EnergyGraph"}
            for i = 1, count do
                local viewName = views[((i - 1) % #views) + 1]
                table.insert(suggestions, { view = viewName, reason = "Test suggestion" })
            end
            return suggestions
        end,
        getDefaultConfig = function(viewName)
            return {}
        end
    }
end

-- Helper: reset module cache for fresh Config load
local function resetConfig()
    module_cache["shelfos/core/Config"] = nil
    module_cache["shelfos/core/ConfigMigration"] = nil
end

-- =============================================================================
-- TESTS: Config.discoverMonitors() - basic discovery
-- =============================================================================

test("discoverMonitors: returns all monitors when only network monitors exist", function()
    Mocks.setupComputer({id = 10, monitors = 0, meBridge = false})
    resetConfig()

    -- Attach 3 network monitors (distinct mock objects)
    local Monitor = require("mocks").Monitor
    Mocks.Peripheral.attach("monitor_0", "monitor", Monitor.new())
    Mocks.Peripheral.attach("monitor_1", "monitor", Monitor.new())
    Mocks.Peripheral.attach("monitor_2", "monitor", Monitor.new())

    local Config = mpm("shelfos/core/Config")
    local monitors, aliases = Config.discoverMonitors()

    assert_eq(3, #monitors, "Should find 3 monitors")
    assert_eq(0, tableCount(aliases), "Should have no aliases (no side monitors)")
    assert_true(arrayContains(monitors, "monitor_0"), "Should contain monitor_0")
    assert_true(arrayContains(monitors, "monitor_1"), "Should contain monitor_1")
    assert_true(arrayContains(monitors, "monitor_2"), "Should contain monitor_2")
end)

test("discoverMonitors: returns side monitor when only side monitors exist", function()
    Mocks.setupComputer({id = 10, monitors = 0, meBridge = false})
    resetConfig()

    local Monitor = require("mocks").Monitor
    Mocks.Peripheral.attach("right", "monitor", Monitor.new())

    local Config = mpm("shelfos/core/Config")
    local monitors, aliases = Config.discoverMonitors()

    assert_eq(1, #monitors, "Should find 1 monitor")
    assert_eq("right", monitors[1], "Should be the side name")
    assert_eq(0, tableCount(aliases), "No aliases needed")
end)

test("discoverMonitors: excludes non-monitor peripherals", function()
    Mocks.setupComputer({id = 10, monitors = 0, meBridge = false})
    resetConfig()

    local Monitor = require("mocks").Monitor
    Mocks.Peripheral.attach("monitor_0", "monitor", Monitor.new())
    -- modem is already attached by setupComputer as "top"

    local Config = mpm("shelfos/core/Config")
    local monitors, aliases = Config.discoverMonitors()

    assert_eq(1, #monitors, "Should only find the monitor, not the modem")
    assert_eq("monitor_0", monitors[1])
end)

-- =============================================================================
-- TESTS: Config.discoverMonitors() - deduplication via cursor fingerprinting
-- =============================================================================

test("discoverMonitors: deduplicates when side and network name point to same monitor", function()
    Mocks.setupComputer({id = 10, monitors = 0, meBridge = false})
    resetConfig()

    -- KEY: same Monitor object attached under both names simulates
    -- the same physical monitor visible under side name AND network name
    local Monitor = require("mocks").Monitor
    local sharedMonitor = Monitor.new()

    Mocks.Peripheral.attach("right", "monitor", sharedMonitor)
    Mocks.Peripheral.attach("monitor_5", "monitor", sharedMonitor)

    local Config = mpm("shelfos/core/Config")
    local monitors, aliases = Config.discoverMonitors()

    -- Should keep "right" (side name), skip "monitor_5" (network name)
    assert_eq(1, #monitors, "Should deduplicate to 1 monitor")
    assert_eq("right", monitors[1], "Should prefer side name")

    -- Alias should map network name to side name
    assert_eq(1, tableCount(aliases), "Should have 1 alias")
    assert_eq("right", aliases["monitor_5"], "monitor_5 should alias to right")
end)

test("discoverMonitors: keeps both when side and network are different physical monitors", function()
    Mocks.setupComputer({id = 10, monitors = 0, meBridge = false})
    resetConfig()

    -- DIFFERENT Monitor objects = different physical monitors
    local Monitor = require("mocks").Monitor
    Mocks.Peripheral.attach("right", "monitor", Monitor.new())
    Mocks.Peripheral.attach("monitor_5", "monitor", Monitor.new())

    local Config = mpm("shelfos/core/Config")
    local monitors, aliases = Config.discoverMonitors()

    assert_eq(2, #monitors, "Should keep both distinct monitors")
    assert_eq(0, tableCount(aliases), "No aliases for distinct monitors")
    assert_true(arrayContains(monitors, "right"))
    assert_true(arrayContains(monitors, "monitor_5"))
end)

test("discoverMonitors: handles multiple side monitors with mixed duplicates", function()
    Mocks.setupComputer({id = 10, monitors = 0, meBridge = false})
    resetConfig()

    local Monitor = require("mocks").Monitor
    local shared1 = Monitor.new()  -- right = monitor_3
    local shared2 = Monitor.new()  -- left = monitor_7
    local standalone = Monitor.new()  -- monitor_10 (no side equivalent)

    Mocks.Peripheral.attach("right", "monitor", shared1)
    Mocks.Peripheral.attach("monitor_3", "monitor", shared1)
    Mocks.Peripheral.attach("left", "monitor", shared2)
    Mocks.Peripheral.attach("monitor_7", "monitor", shared2)
    Mocks.Peripheral.attach("monitor_10", "monitor", standalone)

    local Config = mpm("shelfos/core/Config")
    local monitors, aliases = Config.discoverMonitors()

    -- Should have: right, left, monitor_10 (3 unique)
    assert_eq(3, #monitors, "Should have 3 unique monitors")
    assert_true(arrayContains(monitors, "right"), "Should have right")
    assert_true(arrayContains(monitors, "left"), "Should have left")
    assert_true(arrayContains(monitors, "monitor_10"), "Should have monitor_10")
    assert_false(arrayContains(monitors, "monitor_3"), "Should NOT have monitor_3 (alias)")
    assert_false(arrayContains(monitors, "monitor_7"), "Should NOT have monitor_7 (alias)")

    assert_eq(2, tableCount(aliases), "Should have 2 aliases")
    assert_eq("right", aliases["monitor_3"])
    assert_eq("left", aliases["monitor_7"])
end)

test("discoverMonitors: restores cursor position after fingerprinting", function()
    Mocks.setupComputer({id = 10, monitors = 0, meBridge = false})
    resetConfig()

    local Monitor = require("mocks").Monitor
    local mon = Monitor.new()
    mon:setCursorPos(5, 10)  -- Set known position before discovery

    Mocks.Peripheral.attach("right", "monitor", mon)
    Mocks.Peripheral.attach("monitor_0", "monitor", Monitor.new())  -- different monitor

    local Config = mpm("shelfos/core/Config")
    Config.discoverMonitors()

    -- Cursor should be restored to original position
    local x, y = mon:getCursorPos()
    assert_eq(5, x, "Cursor X should be restored")
    assert_eq(10, y, "Cursor Y should be restored")
end)

-- =============================================================================
-- TESTS: Config.reconcile() - remapping aliases
-- =============================================================================

test("reconcile: remaps network-name config entries to side names", function()
    Mocks.setupComputer({id = 10, monitors = 0, meBridge = false})
    resetConfig()
    installMockViewManager()

    -- Same physical monitor under both names
    local Monitor = require("mocks").Monitor
    local sharedMon = Monitor.new()
    Mocks.Peripheral.attach("right", "monitor", sharedMon)
    Mocks.Peripheral.attach("monitor_5", "monitor", sharedMon)

    local Config = mpm("shelfos/core/Config")

    -- Config still references old network name
    local config = {
        computer = { id = "computer_10", name = "Test" },
        monitors = {
            { peripheral = "monitor_5", label = "monitor_5", view = "StorageGraph", viewConfig = {} }
        },
        network = { enabled = false, secret = nil },
        settings = {}
    }

    local changed, summary = Config.reconcile(config)

    assert_true(changed, "Should report changes")
    assert_eq(1, #config.monitors, "Should still have 1 monitor entry")
    assert_eq("right", config.monitors[1].peripheral, "Should remap to side name")
    assert_eq("right", config.monitors[1].label, "Label should also be remapped")
    assert_eq("StorageGraph", config.monitors[1].view, "View should be preserved")
end)

-- =============================================================================
-- TESTS: Config.reconcile() - deduplication
-- =============================================================================

test("reconcile: removes duplicate entries after remapping", function()
    Mocks.setupComputer({id = 10, monitors = 0, meBridge = false})
    resetConfig()
    installMockViewManager()

    -- Same physical monitor
    local Monitor = require("mocks").Monitor
    local sharedMon = Monitor.new()
    Mocks.Peripheral.attach("right", "monitor", sharedMon)
    Mocks.Peripheral.attach("monitor_5", "monitor", sharedMon)

    local Config = mpm("shelfos/core/Config")

    -- Config has BOTH entries (the bug we're fixing)
    local config = {
        computer = { id = "computer_10", name = "Test" },
        monitors = {
            { peripheral = "right", label = "right", view = "NetworkDashboard", viewConfig = {} },
            { peripheral = "monitor_5", label = "monitor_5", view = "StorageGraph", viewConfig = {} }
        },
        network = { enabled = false, secret = nil },
        settings = {}
    }

    local changed, summary = Config.reconcile(config)

    assert_true(changed, "Should report changes")
    assert_eq(1, #config.monitors, "Should deduplicate to 1 entry")
    assert_eq("right", config.monitors[1].peripheral, "Should keep the first (side) entry")
    assert_eq("NetworkDashboard", config.monitors[1].view, "Should preserve the first entry's view")
end)

test("reconcile: preserves both entries when monitors are distinct", function()
    Mocks.setupComputer({id = 10, monitors = 0, meBridge = false})
    resetConfig()
    installMockViewManager()

    local Monitor = require("mocks").Monitor
    Mocks.Peripheral.attach("right", "monitor", Monitor.new())
    Mocks.Peripheral.attach("monitor_5", "monitor", Monitor.new())

    local Config = mpm("shelfos/core/Config")

    local config = {
        computer = { id = "computer_10", name = "Test" },
        monitors = {
            { peripheral = "right", label = "right", view = "NetworkDashboard", viewConfig = {} },
            { peripheral = "monitor_5", label = "monitor_5", view = "StorageGraph", viewConfig = {} }
        },
        network = { enabled = false, secret = nil },
        settings = {}
    }

    local changed, summary = Config.reconcile(config)

    assert_false(changed, "Should report no changes")
    assert_eq(2, #config.monitors, "Both entries should remain")
end)

-- =============================================================================
-- TESTS: Config.reconcile() - adding new monitors
-- =============================================================================

test("reconcile: adds newly discovered monitors not in config", function()
    Mocks.setupComputer({id = 10, monitors = 0, meBridge = false})
    resetConfig()
    installMockViewManager()

    local Monitor = require("mocks").Monitor
    Mocks.Peripheral.attach("monitor_0", "monitor", Monitor.new())
    Mocks.Peripheral.attach("monitor_1", "monitor", Monitor.new())  -- new, not in config

    local Config = mpm("shelfos/core/Config")

    -- Config only knows about monitor_0
    local config = {
        computer = { id = "computer_10", name = "Test" },
        monitors = {
            { peripheral = "monitor_0", label = "monitor_0", view = "StorageGraph", viewConfig = {} }
        },
        network = { enabled = false, secret = nil },
        settings = {}
    }

    local changed, summary = Config.reconcile(config)

    assert_true(changed, "Should report changes for new monitor")
    assert_eq(2, #config.monitors, "Should now have 2 monitors")
    assert_eq("monitor_0", config.monitors[1].peripheral, "Original should be unchanged")
    assert_eq("StorageGraph", config.monitors[1].view, "Original view preserved")
    assert_eq("monitor_1", config.monitors[2].peripheral, "New monitor should be added")
    assert_not_nil(config.monitors[2].view, "New monitor should have a suggested view")
end)

-- =============================================================================
-- TESTS: Config.reconcile() - no-op when clean
-- =============================================================================

test("reconcile: returns false when config is already clean", function()
    Mocks.setupComputer({id = 10, monitors = 0, meBridge = false})
    resetConfig()
    installMockViewManager()

    local Monitor = require("mocks").Monitor
    Mocks.Peripheral.attach("monitor_0", "monitor", Monitor.new())
    Mocks.Peripheral.attach("monitor_1", "monitor", Monitor.new())

    local Config = mpm("shelfos/core/Config")

    -- Config perfectly matches hardware
    local config = {
        computer = { id = "computer_10", name = "Test" },
        monitors = {
            { peripheral = "monitor_0", label = "monitor_0", view = "StorageGraph", viewConfig = {} },
            { peripheral = "monitor_1", label = "monitor_1", view = "Clock", viewConfig = {} }
        },
        network = { enabled = false, secret = nil },
        settings = {}
    }

    local changed, summary = Config.reconcile(config)

    assert_false(changed, "Should report no changes for clean config")
    assert_nil(summary, "Summary should be nil for clean config")
end)

-- =============================================================================
-- TESTS: Config.reconcile() - combined scenarios
-- =============================================================================

test("reconcile: handles remap + dedup + add in single pass", function()
    Mocks.setupComputer({id = 10, monitors = 0, meBridge = false})
    resetConfig()
    installMockViewManager()

    local Monitor = require("mocks").Monitor
    local sharedMon = Monitor.new()

    -- Hardware: right (=monitor_5), monitor_10 (standalone), monitor_20 (new)
    Mocks.Peripheral.attach("right", "monitor", sharedMon)
    Mocks.Peripheral.attach("monitor_5", "monitor", sharedMon)
    Mocks.Peripheral.attach("monitor_10", "monitor", Monitor.new())
    Mocks.Peripheral.attach("monitor_20", "monitor", Monitor.new())

    local Config = mpm("shelfos/core/Config")

    -- Broken config: has both right and monitor_5 (duplicate), missing monitor_20
    local config = {
        computer = { id = "computer_10", name = "Test" },
        monitors = {
            { peripheral = "right", label = "right", view = "NetworkDashboard", viewConfig = {} },
            { peripheral = "monitor_5", label = "monitor_5", view = "StorageGraph", viewConfig = {} },
            { peripheral = "monitor_10", label = "monitor_10", view = "Clock", viewConfig = {} }
        },
        network = { enabled = false, secret = nil },
        settings = {}
    }

    local changed, summary = Config.reconcile(config)

    assert_true(changed, "Should report changes")

    -- After reconcile: right (kept, dedup'd monitor_5), monitor_10, monitor_20 (added)
    assert_eq(3, #config.monitors, "Should have 3 monitors after reconcile")
    assert_eq("right", config.monitors[1].peripheral)
    assert_eq("NetworkDashboard", config.monitors[1].view, "First entry view preserved")
    assert_eq("monitor_10", config.monitors[2].peripheral)
    assert_eq("Clock", config.monitors[2].view, "Existing entry view preserved")
    assert_eq("monitor_20", config.monitors[3].peripheral, "New monitor added")
end)

test("reconcile: remaps config entry when only network name existed (no side entry)", function()
    Mocks.setupComputer({id = 10, monitors = 0, meBridge = false})
    resetConfig()
    installMockViewManager()

    local Monitor = require("mocks").Monitor
    local sharedMon = Monitor.new()

    -- Hardware: left = monitor_3 (same physical device)
    Mocks.Peripheral.attach("left", "monitor", sharedMon)
    Mocks.Peripheral.attach("monitor_3", "monitor", sharedMon)

    local Config = mpm("shelfos/core/Config")

    -- Config only has the network name (user never saw side name before)
    local config = {
        computer = { id = "computer_10", name = "Test" },
        monitors = {
            { peripheral = "monitor_3", label = "My Display", view = "EnergyGraph", viewConfig = { unit = "RF" } }
        },
        network = { enabled = false, secret = nil },
        settings = {}
    }

    local changed, summary = Config.reconcile(config)

    assert_true(changed, "Should report changes")
    assert_eq(1, #config.monitors, "Should still have 1 entry")
    assert_eq("left", config.monitors[1].peripheral, "Should remap to side name")
    assert_eq("left", config.monitors[1].label, "Label should be updated to side name")
    assert_eq("EnergyGraph", config.monitors[1].view, "View should be preserved")
    assert_eq("RF", config.monitors[1].viewConfig.unit, "viewConfig should be preserved")
end)

-- =============================================================================
-- TESTS: Config.reconcile() - edge cases
-- =============================================================================

test("reconcile: handles empty monitors array in config", function()
    Mocks.setupComputer({id = 10, monitors = 0, meBridge = false})
    resetConfig()
    installMockViewManager()

    local Monitor = require("mocks").Monitor
    Mocks.Peripheral.attach("monitor_0", "monitor", Monitor.new())

    local Config = mpm("shelfos/core/Config")

    local config = {
        computer = { id = "computer_10", name = "Test" },
        monitors = {},
        network = { enabled = false, secret = nil },
        settings = {}
    }

    local changed, summary = Config.reconcile(config)

    assert_true(changed, "Should add the discovered monitor")
    assert_eq(1, #config.monitors, "Should have 1 monitor now")
    assert_eq("monitor_0", config.monitors[1].peripheral)
end)

test("reconcile: handles no hardware monitors at all", function()
    Mocks.setupComputer({id = 10, monitors = 0, meBridge = false})
    resetConfig()
    installMockViewManager()

    -- No monitors attached at all

    local Config = mpm("shelfos/core/Config")

    local config = {
        computer = { id = "computer_10", name = "Test" },
        monitors = {
            { peripheral = "monitor_0", label = "monitor_0", view = "Clock", viewConfig = {} }
        },
        network = { enabled = false, secret = nil },
        settings = {}
    }

    -- Config references monitors that no longer exist physically
    -- reconcile doesn't remove stale entries (monitor might be temporarily disconnected)
    local changed, summary = Config.reconcile(config)

    -- No remapping needed, no duplicates, no new monitors to add
    assert_false(changed, "Should not change config when no hardware monitors exist")
    assert_eq(1, #config.monitors, "Stale entry should remain (might reconnect)")
end)

test("discoverMonitors: returns empty when no monitors attached", function()
    Mocks.setupComputer({id = 10, monitors = 0, meBridge = false})
    resetConfig()

    local Config = mpm("shelfos/core/Config")
    local monitors, aliases = Config.discoverMonitors()

    assert_eq(0, #monitors, "Should find 0 monitors")
    assert_eq(0, tableCount(aliases), "No aliases")
end)
