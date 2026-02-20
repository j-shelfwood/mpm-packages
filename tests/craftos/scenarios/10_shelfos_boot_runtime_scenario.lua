return function(h)
    local function wipe(path)
        if fs.exists(path) then
            fs.delete(path)
        end
    end

    h:test("shelfos runtime: start.lua routes pocket or unified kernel", function()
        local startPath = h.workspace .. "/shelfos/start.lua"
        local chunk = assert(loadfile(startPath))

        local oldPocket = _G.pocket
        local oldPeripheral = _G.peripheral
        local oldMpm = _G.mpm
        local oldPrint = _G.print

        local prints = {}
        local kernelBoots = 0
        local kernelRuns = 0

        _G.print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do
                parts[#parts + 1] = tostring(select(i, ...))
            end
            prints[#prints + 1] = table.concat(parts, " ")
        end

        _G.pocket = {}
        _G.peripheral = {
            find = function()
                return nil
            end
        }
        _G.mpm = function()
            error("mpm should not be called in pocket mode guidance path")
        end

        chunk()
        h:assert_contains(table.concat(prints, "\n"), "mpm run shelfos-swarm", "Pocket guidance text missing")

        _G.pocket = nil
        _G.peripheral = {
            find = function(kind)
                if kind == "monitor" then
                    return function() end
                end
                return nil
            end
        }
        _G.mpm = function(name)
            if name == "shelfos/core/Kernel" then
                return {
                    new = function()
                        return {
                            boot = function()
                                kernelBoots = kernelBoots + 1
                                return true
                            end,
                            run = function()
                                kernelRuns = kernelRuns + 1
                            end
                        }
                    end
                }
            end
            error("Unexpected module request in default kernel path: " .. tostring(name))
        end

        chunk()

        _G.mpm = function(name)
            if name == "shelfos/core/Kernel" then
                return {
                    new = function()
                        return {
                            boot = function()
                                kernelBoots = kernelBoots + 1
                                return true
                            end,
                            run = function()
                                kernelRuns = kernelRuns + 1
                            end
                        }
                    end
                }
            end
            error("Unexpected module request in host compatibility path: " .. tostring(name))
        end

        chunk("host")

        _G.pocket = oldPocket
        _G.peripheral = oldPeripheral
        _G.mpm = oldMpm
        _G.print = oldPrint

        h:assert_eq(2, kernelBoots, "Default and host invocations should both boot Kernel")
        h:assert_eq(2, kernelRuns, "Default and host invocations should both run Kernel")
    end)

    h:test("shelfos runtime: config migration handles legacy displays and zone key", function()
        local Config = mpm("shelfos/core/Config")

        wipe("/displays.config")
        wipe("/shelfos.config")

        local legacy = {
            displays = {
                { monitor = "left", view = "Clock", config = { timeFormat = "24h" } },
                { monitor = "right", view = "EnergyStatus" }
            },
            settings = { theme = "solarized" }
        }

        local writeLegacy = fs.open("/displays.config", "w")
        h:assert_not_nil(writeLegacy, "Failed to create /displays.config")
        writeLegacy.write(textutils.serialize(legacy))
        writeLegacy.close()

        local migrated = Config.load()
        h:assert_not_nil(migrated, "Expected migrated config")
        h:assert_eq(2, #migrated.monitors, "Expected legacy displays to migrate to monitors")
        h:assert_eq("solarized", migrated.settings.theme, "Expected legacy theme migration")
        h:assert_false(fs.exists("/displays.config"), "Legacy displays.config should be removed after migration")
        h:assert_true(fs.exists("/shelfos.config"), "Migrated config should be saved")

        local zoneConfig = {
            version = 1,
            zone = {
                id = "zone_99",
                name = "Legacy Zone"
            },
            monitors = {},
            network = {
                secret = "secret-x",
                enabled = true
            }
        }

        local writeConfig = fs.open("/shelfos.config", "w")
        h:assert_not_nil(writeConfig, "Failed to write /shelfos.config")
        writeConfig.write(textutils.serialize(zoneConfig))
        writeConfig.close()

        local loaded = Config.load()
        h:assert_not_nil(loaded.computer, "Zone key should be migrated to computer")
        h:assert_eq("zone_99", loaded.computer.id, "Computer id should come from legacy zone key")
        h:assert_true(loaded.zone == nil, "Legacy zone key should be cleared")

        wipe("/shelfos.config")
    end)

    h:test("shelfos runtime: reconcile remaps aliases, view renames, and new monitors", function()
        local Config = mpm("shelfos/core/Config")

        local originalDiscover = Config.discoverMonitors
        local originalMpm = _G.mpm

        local fakeViewManager = {
            getAvailableViews = function()
                return { "MachineGrid", "Clock" }
            end,
            getDefaultConfig = function(view)
                return { defaultFor = view }
            end,
            suggestView = function()
                return "Clock", "fallback"
            end,
            suggestViewsForMonitors = function(count)
                local out = {}
                for i = 1, count do
                    out[i] = { view = "Clock", reason = "Default" }
                end
                return out
            end
        }

        Config.discoverMonitors = function()
            return { "left", "right" }, { ["monitor_9"] = "left" }
        end

        _G.mpm = function(name)
            if name == "views/Manager" then
                return fakeViewManager
            end
            return originalMpm(name)
        end

        local config = {
            monitors = {
                { peripheral = "monitor_9", label = "monitor_9", view = "MachineActivity", viewConfig = {} },
                { peripheral = "left", label = "left", view = "GhostView", viewConfig = {} }
            }
        }

        local changed, summary = Config.reconcile(config)

        Config.discoverMonitors = originalDiscover
        _G.mpm = originalMpm

        h:assert_true(changed, "Reconcile should report config changes")
        h:assert_not_nil(summary, "Reconcile should provide a change summary")
        h:assert_eq(2, #config.monitors, "Reconcile should dedupe and include newly discovered monitor")

        local byPeripheral = {}
        for _, entry in ipairs(config.monitors) do
            byPeripheral[entry.peripheral] = entry
        end

        h:assert_not_nil(byPeripheral.left, "Expected canonical left monitor entry")
        h:assert_not_nil(byPeripheral.right, "Expected new right monitor entry")
        h:assert_eq("MachineGrid", byPeripheral.left.view, "View rename should migrate MachineActivity -> MachineGrid")
        h:assert_eq("Clock", byPeripheral.right.view, "New monitor should receive suggested fallback view")
    end)
end
