return function(h)
    local function build_app_stub()
        local computers = {}
        for i = 1, 12 do
            computers[#computers + 1] = {
                id = "computer_" .. i,
                label = "Computer " .. i,
                fingerprint = "FP-" .. i,
                status = "active"
            }
        end

        return {
            authority = {
                getInfo = function()
                    return {
                        name = "Test Swarm",
                        fingerprint = "FP-TEST-0001",
                        computerCount = #computers
                    }
                end,
                getComputers = function()
                    return computers
                end,
                deleteSwarm = function() end
            },
            channel = nil
        }
    end

    local function press(manager, driver, keyName)
        local screen = manager:current()
        local event = driver:key_event(keyName)
        local action = screen.handleEvent(manager.ctx, event[1], event[2], event[3])
        if action then
            manager:processAction(action)
        end
    end

    h:test("UI keystrokes: navigate main menu -> view computers -> back", function()
        h:with_ui_driver(51, 19, function(driver)
            local app = build_app_stub()
            local ScreenManager = mpm("shelfos-swarm/ui/ScreenManager")
            local MainMenu = mpm("shelfos-swarm/screens/MainMenu")

            local manager = ScreenManager.new(app)
            manager:push(MainMenu)

            h:assert_screen_contains(driver, "Test Swarm", "Main menu title should render")
            h:assert_screen_contains(driver, "[A] Add Computer", "Main menu options should render")
            h:assert_screen_contains(driver, "[C] View Computers", "Main menu options should render")

            press(manager, driver, "c")
            h:assert_screen_contains(driver, "Computer Registry", "Should navigate to ViewComputers screen")
            h:assert_screen_contains(driver, "Page 1/2", "Initial page indicator should render")

            for _ = 1, 6 do
                press(manager, driver, "down")
            end
            h:assert_screen_contains(driver, "Page 2/2", "Down key should scroll into next page")

            press(manager, driver, "b")
            h:assert_screen_contains(driver, "[A] Add Computer", "Back should return to main menu")
        end)
    end)

    h:test("UI keystrokes: open reboot screen and assert error state renders", function()
        h:with_ui_driver(51, 19, function(driver)
            local app = build_app_stub()
            local ScreenManager = mpm("shelfos-swarm/ui/ScreenManager")
            local MainMenu = mpm("shelfos-swarm/screens/MainMenu")

            local manager = ScreenManager.new(app)
            manager:push(MainMenu)

            press(manager, driver, "r")
            h:assert_screen_contains(driver, "REBOOT SWARM", "Should open reboot confirmation screen")
            h:assert_screen_contains(driver, "[Y] Reboot", "Reboot confirmation controls should render")

            press(manager, driver, "y")
            h:assert_screen_contains(driver, "No network channel. Restart app.", "Missing channel should render deterministic error")

            press(manager, driver, "n")
            h:assert_screen_contains(driver, "[A] Add Computer", "Cancel from error should return to main menu")
        end)
    end)

    h:test("UI keystrokes: open delete screen and cancel without side effects", function()
        h:with_ui_driver(51, 19, function(driver)
            local app = build_app_stub()
            local ScreenManager = mpm("shelfos-swarm/ui/ScreenManager")
            local MainMenu = mpm("shelfos-swarm/screens/MainMenu")

            local manager = ScreenManager.new(app)
            manager:push(MainMenu)

            press(manager, driver, "d")
            h:assert_screen_contains(driver, "DELETE SWARM", "Delete confirmation should render")
            h:assert_screen_contains(driver, "[N] Cancel", "Delete confirmation controls should render")

            press(manager, driver, "n")
            h:assert_screen_contains(driver, "[A] Add Computer", "Cancel should pop back to main menu")
        end)
    end)
end
