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
                return { "MachineGrid", "EnergyFlowGraph", "Clock" }
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
            return { "left", "right", "top" }, { ["monitor_9"] = "left" }
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
                { peripheral = "top", label = "top", view = "EnergyFlow", viewConfig = {} }
            }
        }

        local changed, summary = Config.reconcile(config)

        Config.discoverMonitors = originalDiscover
        _G.mpm = originalMpm

        h:assert_true(changed, "Reconcile should report config changes")
        h:assert_not_nil(summary, "Reconcile should provide a change summary")
        h:assert_eq(3, #config.monitors, "Reconcile should include remapped + migrated + newly discovered monitors")

        local byPeripheral = {}
        for _, entry in ipairs(config.monitors) do
            byPeripheral[entry.peripheral] = entry
        end

        h:assert_not_nil(byPeripheral.left, "Expected canonical left monitor entry")
        h:assert_not_nil(byPeripheral.top, "Expected existing top monitor entry")
        h:assert_not_nil(byPeripheral.right, "Expected new right monitor entry")
        h:assert_eq("MachineGrid", byPeripheral.left.view, "View rename should migrate MachineActivity -> MachineGrid")
        h:assert_eq("EnergyFlowGraph", byPeripheral.top.view, "View rename should migrate EnergyFlow -> EnergyFlowGraph")
        h:assert_eq("Clock", byPeripheral.right.view, "New monitor should receive suggested fallback view")
    end)

    h:test("shelfos runtime: reconcile prunes stale configured monitors", function()
        local Config = mpm("shelfos/core/Config")

        local originalDiscover = Config.discoverMonitors
        local originalMpm = _G.mpm

        local fakeViewManager = {
            getAvailableViews = function()
                return { "Clock" }
            end,
            getDefaultConfig = function()
                return {}
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
            return { "left" }, {}
        end

        _G.mpm = function(name)
            if name == "views/Manager" then
                return fakeViewManager
            end
            return originalMpm(name)
        end

        local config = {
            monitors = {
                { peripheral = "left", label = "left", view = "Clock", viewConfig = {} },
                { peripheral = "monitor_99", label = "monitor_99", view = "Clock", viewConfig = {} }
            }
        }

        local changed, summary = Config.reconcile(config)

        Config.discoverMonitors = originalDiscover
        _G.mpm = originalMpm

        h:assert_true(changed, "Expected stale monitor to be removed")
        h:assert_not_nil(summary, "Expected reconcile summary")
        h:assert_eq(1, #config.monitors, "Expected stale configured monitor entry to be pruned")
        h:assert_eq("left", config.monitors[1].peripheral, "Expected canonical monitor to remain")
    end)

    h:test("shelfos runtime: Config.renameMonitor rewrites peripheral and preserves custom label", function()
        local Config = mpm("shelfos/core/Config")
        local config = {
            monitors = {
                { peripheral = "monitor_9", label = "Mixer Wall", view = "Clock", viewConfig = {} }
            }
        }

        local changed = Config.renameMonitor(config, "monitor_9", "left")
        h:assert_true(changed, "Expected renameMonitor to update matching entry")
        h:assert_eq("left", config.monitors[1].peripheral, "Expected peripheral name update")
        h:assert_eq("Mixer Wall", config.monitors[1].label, "Expected custom label preserved")
    end)

    h:test("shelfos runtime: PairingScreen uses canonical discoverMonitors list", function()
        local oldMpm = _G.mpm
        local oldPeripheral = _G.peripheral

        local drawCalls = {}
        _G.peripheral = {
            wrap = function(name)
                return {
                    getSize = function() return 10, 4 end,
                    setTextScale = function() end,
                    setBackgroundColor = function() end,
                    clear = function() end,
                    setTextColor = function() end,
                    setCursorPos = function() end,
                    write = function(_, text)
                        drawCalls[#drawCalls + 1] = { name = name, text = text }
                    end
                }
            end,
            getNames = function()
                error("drawOnAllMonitors should use Config.discoverMonitors, not peripheral.getNames")
            end
        }

        _G.mpm = function(name)
            if name == "shelfos/core/Config" then
                return {
                    discoverMonitors = function()
                        return { "left", "right" }, { monitor_1 = "left" }
                    end
                }
            end
            return oldMpm(name)
        end

        local PairingScreen = assert(loadfile(h.workspace .. "/shelfos/ui/PairingScreen.lua"))()
        local names = PairingScreen.drawOnAllMonitors("ABCD-EFGH", "Node A")

        _G.mpm = oldMpm
        _G.peripheral = oldPeripheral

        h:assert_eq(2, #names, "Expected canonical monitor names from discoverMonitors")
        h:assert_eq("left", names[1], "Expected first canonical monitor")
        h:assert_eq("right", names[2], "Expected second canonical monitor")
        h:assert_true(#drawCalls > 0, "Expected draw activity on discovered monitors")
    end)

    h:test("shelfos runtime: Monitor runLoop reconnects on attach and disconnects on detach", function()
        local Monitor = mpm("shelfos/core/Monitor")
        local oldPullEvent = os.pullEvent

        local reconnects = 0
        local disconnects = 0
        local renders = 0
        local schedules = 0
        local index = 0
        local running = { value = true }

        local instance = setmetatable({
            peripheralName = "left",
            connected = false,
            inConfigMenu = false,
            pairingMode = false,
            viewInstance = nil,
            reconnect = function(self)
                reconnects = reconnects + 1
                self.connected = true
                self.viewInstance = {}
                return true
            end,
            disconnect = function(self)
                disconnects = disconnects + 1
                self.connected = false
            end,
            render = function()
                renders = renders + 1
            end,
            scheduleRender = function()
                schedules = schedules + 1
            end,
            scheduleLoadRetry = function()
                error("scheduleLoadRetry should not run for disconnected start")
            end,
            handleTimer = function() end,
            handleTouch = function() end,
            handleResize = function() end
        }, Monitor)

        os.pullEvent = function()
            index = index + 1
            if index == 1 then
                return "peripheral", "left"
            elseif index == 2 then
                return "peripheral_detach", "left"
            else
                running.value = false
                return "timer", 999
            end
        end

        instance:runLoop(running)
        os.pullEvent = oldPullEvent

        h:assert_eq(1, reconnects, "Expected reconnect on peripheral attach")
        h:assert_eq(1, disconnects, "Expected disconnect on peripheral_detach")
        h:assert_true(renders >= 1, "Expected render after reconnect")
        h:assert_true(schedules >= 1, "Expected scheduleRender after reconnect")
    end)

    h:test("shelfos runtime: Kernel recovers detached monitor by adopting new peripheral name", function()
        local Kernel = mpm("shelfos/core/Kernel")
        local Config = mpm("shelfos/core/Config")
        local oldPeripheral = _G.peripheral

        local saveCalls = 0
        local originalSave = Config.save
        Config.save = function(cfg)
            saveCalls = saveCalls + 1
            return true
        end

        _G.peripheral = {
            hasType = function(name, pType)
                return name == "monitor_17" and pType == "monitor"
            end
        }

        local adoptedFrom, adoptedTo = nil, nil
        local kernel = Kernel.new()
        kernel.config = {
            monitors = {
                { peripheral = "monitor_9", label = "monitor_9", view = "Clock", viewConfig = {} }
            }
        }
        kernel.monitors = {
            {
                isConnected = function() return false end,
                getPeripheralName = function() return "monitor_9" end,
                adoptPeripheralName = function(_, newName)
                    adoptedFrom = "monitor_9"
                    adoptedTo = newName
                    return true
                end
            }
        }

        local recovered = kernel:recoverDetachedMonitor("monitor_17")

        Config.save = originalSave
        _G.peripheral = oldPeripheral

        h:assert_true(recovered, "Expected kernel to recover detached monitor")
        h:assert_eq("monitor_9", adoptedFrom, "Expected disconnected monitor candidate to be adopted")
        h:assert_eq("monitor_17", adoptedTo, "Expected new peripheral name adoption")
        h:assert_eq("monitor_17", kernel.config.monitors[1].peripheral, "Expected config monitor name update")
        h:assert_true(saveCalls >= 1, "Expected config save after monitor rename")
    end)
end
