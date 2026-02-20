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

    h:test("unified kernel contract: legacy headless artifacts removed", function()
        h:assert_false(fs.exists(h.workspace .. "/shelfos/modes/headless.lua"), "legacy headless mode should be removed")
        h:assert_false(fs.exists(h.workspace .. "/shelfos/tools/pair_accept.lua"), "legacy pair_accept tool should be removed")
        h:assert_true(fs.exists(h.workspace .. "/shelfos/core/Kernel.lua"), "Kernel entrypoint should exist")
    end)
end
