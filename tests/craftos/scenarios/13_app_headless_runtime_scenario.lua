return function(h)
    h:test("swarm app init: existing swarm initializes MainMenu path", function()
        local App = mpm("shelfos-swarm/App")
        local MainMenu = mpm("shelfos-swarm/screens/MainMenu")
        local ModemUtils = mpm("utils/ModemUtils")

        local app = App.new()
        app.authority.exists = function() return true end
        app.authority.init = function() return true end
        app.authority.getInfo = function()
            return {
                name = "Prod Swarm",
                computerCount = 3,
                fingerprint = "FP-PROD"
            }
        end

        local initNetworkCalls = 0
        app.initNetwork = function()
            initNetworkCalls = initNetworkCalls + 1
            return true
        end

        local originalFind = ModemUtils.find
        local originalSleep = _G.sleep

        ModemUtils.find = function()
            return {}, "back", "wireless"
        end
        _G.sleep = function() end

        local ok = app:init()

        ModemUtils.find = originalFind
        _G.sleep = originalSleep

        h:assert_true(ok, "App:init should succeed when swarm and modem are available")
        h:assert_eq(1, initNetworkCalls, "App:init should initialize network once")
        h:assert_true(app.initialScreen == MainMenu, "App:init should set MainMenu as initial screen")
    end)

    h:test("swarm app init: corrupted swarm data supports reset and reboot path", function()
        local App = mpm("shelfos-swarm/App")
        local ModemUtils = mpm("utils/ModemUtils")

        local app = App.new()
        local deleted = 0
        app.authority.exists = function() return true end
        app.authority.init = function() return false end
        app.authority.deleteSwarm = function()
            deleted = deleted + 1
        end

        local originalFind = ModemUtils.find
        local originalPullEvent = os.pullEvent
        local originalReboot = os.reboot
        local originalSleep = _G.sleep

        ModemUtils.find = function()
            return {}, "back", "wireless"
        end

        local events = {
            { "key", keys.r }
        }

        os.pullEvent = function(filter)
            local nextEvent = table.remove(events, 1)
            if nextEvent then
                return unpack(nextEvent)
            end
            return "key", keys.q
        end

        local rebooted = false
        os.reboot = function()
            rebooted = true
            error("reboot_called")
        end

        _G.sleep = function() end

        local ok, err = pcall(function()
            app:init()
        end)

        ModemUtils.find = originalFind
        os.pullEvent = originalPullEvent
        os.reboot = originalReboot
        _G.sleep = originalSleep

        h:assert_false(ok, "Reset path should end in reboot")
        h:assert_contains(tostring(err), "reboot_called", "Expected reboot sentinel error")
        h:assert_eq(1, deleted, "Reset path should delete swarm exactly once")
        h:assert_true(rebooted, "Reset path should reboot")
    end)

    h:test("headless runtime: exits early when no monitor and no modem", function()
        local headless = mpm("shelfos/modes/headless")
        local Config = mpm("shelfos/core/Config")
        local ModemUtils = mpm("utils/ModemUtils")

        local originalLoad = Config.load
        local originalCreate = Config.create
        local originalSave = Config.save
        local originalHasAny = ModemUtils.hasAny
        local originalPeripheral = _G.peripheral
        local originalPullEvent = os.pullEvent

        Config.load = function()
            return {
                computer = { id = "node_1", name = "Node 1" },
                network = { secret = nil, enabled = false }
            }
        end
        Config.create = function()
            error("Config.create should not be used when load() succeeds")
        end
        Config.save = function()
            return true
        end

        ModemUtils.hasAny = function()
            return false
        end
        _G.peripheral = {
            find = function(kind)
                return nil
            end
        }

        local pullCount = 0
        os.pullEvent = function(filter)
            pullCount = pullCount + 1
            return "key", keys.q
        end

        local ok, err = pcall(function()
            headless.run()
        end)

        Config.load = originalLoad
        Config.create = originalCreate
        Config.save = originalSave
        ModemUtils.hasAny = originalHasAny
        _G.peripheral = originalPeripheral
        os.pullEvent = originalPullEvent

        h:assert_true(ok, "headless.run should return cleanly in no-monitor/no-modem guard path: " .. tostring(err))
        h:assert_true(pullCount >= 1, "Expected key wait before exiting guard path")
    end)

    h:test("headless runtime: successful pairing persists secret and reboots", function()
        local headless = mpm("shelfos/modes/headless")
        local Config = mpm("shelfos/core/Config")
        local ModemUtils = mpm("utils/ModemUtils")

        local originalLoad = Config.load
        local originalCreate = Config.create
        local originalSave = Config.save
        local originalSetNetworkSecret = Config.setNetworkSecret
        local originalHasAny = ModemUtils.hasAny
        local originalPeripheral = _G.peripheral
        local originalPullEvent = os.pullEvent
        local originalReboot = os.reboot
        local originalSleep = _G.sleep
        local originalAcceptPairing = headless.acceptPairing

        local savedConfig = nil
        local setSecretCalls = 0

        Config.load = function()
            return {
                computer = { id = "computer_old", name = "Node" },
                network = { secret = nil, enabled = false }
            }
        end
        Config.create = function()
            error("Config.create should not run when Config.load succeeds")
        end
        Config.setNetworkSecret = function(config, secret)
            setSecretCalls = setSecretCalls + 1
            config.network.secret = secret
            config.network.enabled = true
        end
        Config.save = function(config)
            savedConfig = config
            return true
        end

        ModemUtils.hasAny = function()
            return true
        end
        _G.peripheral = {
            find = function(kind)
                return nil
            end
        }

        local events = {
            { "key", keys.l }
        }
        os.pullEvent = function(filter)
            local ev = table.remove(events, 1)
            if ev then
                return unpack(ev)
            end
            return "key", keys.q
        end

        headless.acceptPairing = function(config)
            return true, "new-secret-xyz", "computer_new"
        end

        _G.sleep = function() end

        local rebooted = false
        os.reboot = function()
            rebooted = true
            error("reboot_called")
        end

        local ok, err = pcall(function()
            headless.run()
        end)

        Config.load = originalLoad
        Config.create = originalCreate
        Config.save = originalSave
        Config.setNetworkSecret = originalSetNetworkSecret
        ModemUtils.hasAny = originalHasAny
        _G.peripheral = originalPeripheral
        os.pullEvent = originalPullEvent
        os.reboot = originalReboot
        _G.sleep = originalSleep
        headless.acceptPairing = originalAcceptPairing

        h:assert_false(ok, "Successful pairing path should reboot")
        h:assert_contains(tostring(err), "reboot_called", "Expected reboot sentinel on successful pairing")
        h:assert_eq(1, setSecretCalls, "Pairing should set network secret exactly once")
        h:assert_not_nil(savedConfig, "Pairing should persist updated config")
        h:assert_eq("new-secret-xyz", savedConfig.network.secret, "Saved config should contain new secret")
        h:assert_eq("computer_new", savedConfig.computer.id, "Saved config should update computer id from pairing")
        h:assert_true(rebooted, "Pairing success should trigger reboot")
    end)
end
