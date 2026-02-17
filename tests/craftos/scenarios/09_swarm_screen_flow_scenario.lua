return function(h)
    local function press(manager, keyName)
        local driver = manager.__driver
        local screen = manager:current()
        local event = driver:key_event(keyName)
        local action = screen.handleEvent(manager.ctx, event[1], event[2], event[3])
        if action then
            manager:processAction(action)
        end
        return action
    end

    local function build_app_stub(computers)
        local app = {
            createdSwarmName = nil,
            issued = {},
            removed = {},
            initNetworkCalls = 0,
            authority = {},
            channel = nil
        }

        app.authority.getInfo = function()
            return {
                name = app.createdSwarmName or "Test Swarm",
                fingerprint = "FP-TEST-0001",
                computerCount = #computers
            }
        end

        app.authority.getComputers = function()
            return computers
        end

        app.authority.issueCredentials = function(_, id, label)
            app.issued[#app.issued + 1] = { id = id, label = label }
            return {
                computerId = id,
                computerSecret = "comp-secret-" .. id,
                swarmId = "swarm-test",
                swarmSecret = "swarm-secret",
                swarmFingerprint = "FP-TEST-0001"
            }
        end

        app.authority.removeComputer = function(_, id)
            app.removed[#app.removed + 1] = id
        end

        app.authority.createSwarm = function(_, name)
            app.createdSwarmName = name
            return true, "swarm-created"
        end

        app.authority.deleteSwarm = function() end

        app.initNetwork = function()
            app.initNetworkCalls = app.initNetworkCalls + 1
            return true
        end

        return app
    end

    h:test("screen flow: AddComputer scan/select/code success transitions", function()
        h:with_ui_driver(51, 19, function(driver)
            local Protocol = mpm("net/Protocol")
            local ModemUtils = mpm("utils/ModemUtils")
            local ScreenManager = mpm("shelfos-swarm/ui/ScreenManager")
            local MainMenu = mpm("shelfos-swarm/screens/MainMenu")

            local app = build_app_stub({})
            local manager = ScreenManager.new(app)
            manager.__driver = driver

            local originalOpen = ModemUtils.open
            local originalRead = _G.read
            local originalRednet = _G.rednet

            local sent = {}
            ModemUtils.open = function()
                return true, "back", "wireless"
            end
            _G.read = function()
                return "ABCD-1234"
            end
            _G.rednet = {
                send = function(id, message, protocol)
                    sent[#sent + 1] = { id = id, message = message, protocol = protocol }
                    return true
                end,
                broadcast = function() return true end
            }

            manager:push(MainMenu)
            press(manager, "a")

            local pairReady = Protocol.createPairReady(nil, "Node Alpha", "node_alpha")
            local current = manager:current()
            current.handleEvent(manager.ctx, "rednet_message", 101, pairReady, "shelfos_pair")
            h:assert_screen_contains(driver, "Found: 1 computer(s)", "Scan phase should show discovered computer")

            press(manager, "s")
            h:assert_screen_contains(driver, "Select a computer to pair:", "Should switch to selecting phase")
            h:assert_screen_contains(driver, "[1] Node Alpha", "Discovered computer should be selectable")

            os.queueEvent("rednet_message", 101, Protocol.createPairComplete("Node Alpha"), "shelfos_pair")
            press(manager, "one")

            h:assert_screen_contains(driver, "Computer Paired!", "Success screen should render")
            h:assert_screen_contains(driver, "Node Alpha joined swarm", "Success message should include computer label")
            h:assert_true(#app.issued == 1, "Credentials should be issued exactly once")
            h:assert_true(#sent >= 1, "PAIR_DELIVER should be sent")

            press(manager, "space")
            h:assert_screen_contains(driver, "[A] Add Computer", "Success keypress should return to main menu")

            ModemUtils.open = originalOpen
            _G.read = originalRead
            _G.rednet = originalRednet
        end)
    end)

    h:test("screen flow: AddComputer timeout removes pending registration", function()
        h:with_ui_driver(51, 19, function(driver)
            local Protocol = mpm("net/Protocol")
            local ModemUtils = mpm("utils/ModemUtils")
            local ScreenManager = mpm("shelfos-swarm/ui/ScreenManager")
            local MainMenu = mpm("shelfos-swarm/screens/MainMenu")

            local app = build_app_stub({})
            local manager = ScreenManager.new(app)
            manager.__driver = driver

            local originalOpen = ModemUtils.open
            local originalRead = _G.read
            local originalRednet = _G.rednet

            local fakeNow = 0
            ModemUtils.open = function()
                return true, "back", "wireless"
            end
            _G.read = function()
                return "WXYZ-9999"
            end
            _G.rednet = {
                send = function() return true end,
                broadcast = function() return true end
            }

            manager:push(MainMenu)
            press(manager, "a")

            local pairReady = Protocol.createPairReady(nil, "Node Timeout", "node_timeout")
            local current = manager:current()
            current.handleEvent(manager.ctx, "rednet_message", 202, pairReady, "shelfos_pair")
            press(manager, "s")

            h:with_overrides(os, {
                epoch = function()
                    return fakeNow
                end,
                startTimer = function()
                    return 1
                end,
                pullEvent = function()
                    fakeNow = fakeNow + 6000
                    return "timer", 1
                end
            }, function()
                press(manager, "one")
            end)

            h:assert_screen_contains(driver, "No response - check code was correct", "Timeout should render deterministic error")
            h:assert_eq("node_timeout", app.removed[1], "Failed pair should clean up pending computer")

            press(manager, "space")
            h:assert_screen_contains(driver, "[A] Add Computer", "Error keypress should return to main menu")

            ModemUtils.open = originalOpen
            _G.read = originalRead
            _G.rednet = originalRednet
        end)
    end)

    h:test("screen flow: CreateSwarm runs input -> creating -> success -> main menu", function()
        h:with_ui_driver(51, 19, function(driver)
            local ScreenManager = mpm("shelfos-swarm/ui/ScreenManager")
            local MainMenu = mpm("shelfos-swarm/screens/MainMenu")
            local CreateSwarm = mpm("shelfos-swarm/screens/CreateSwarm")

            local app = build_app_stub({})
            local manager = ScreenManager.new(app)
            manager.__driver = driver

            local originalRead = _G.read
            _G.read = function()
                return "Factory Floor"
            end

            manager:push(MainMenu)
            manager:push(CreateSwarm)

            h:assert_screen_contains(driver, "Swarm created!", "CreateSwarm should reach success phase")
            h:assert_screen_contains(driver, "Factory Floor", "Success screen should show chosen swarm name")
            h:assert_eq(1, app.initNetworkCalls, "CreateSwarm should initialize network once")

            press(manager, "space")
            h:assert_screen_contains(driver, "Factory Floor", "Return to MainMenu should reflect newly created swarm")

            _G.read = originalRead
        end)
    end)

    h:test("screen flow: ViewComputers scrolling updates reachable page indicators on large registry", function()
        h:with_ui_driver(51, 19, function(driver)
            local ScreenManager = mpm("shelfos-swarm/ui/ScreenManager")
            local MainMenu = mpm("shelfos-swarm/screens/MainMenu")
            local ViewComputers = mpm("shelfos-swarm/screens/ViewComputers")

            local computers = {}
            for i = 1, 28 do
                computers[#computers + 1] = {
                    id = "node_" .. i,
                    label = "Node " .. i,
                    fingerprint = "FP-" .. i,
                    status = "active"
                }
            end

            local app = build_app_stub(computers)
            local manager = ScreenManager.new(app)
            manager.__driver = driver

            manager:push(MainMenu)
            manager:push(ViewComputers)

            h:assert_screen_contains(driver, "Page 1/5", "Initial page should reflect reachable page count")
            for _ = 1, 5 do
                press(manager, "down")
            end
            h:assert_screen_contains(driver, "Page 2/5", "Down scrolling should advance page")
            for _ = 1, 5 do
                press(manager, "down")
            end
            h:assert_screen_contains(driver, "Page 3/5", "Further down scrolling should advance again")
            for _ = 1, 5 do
                press(manager, "up")
            end
            h:assert_screen_contains(driver, "Page 2/5", "Up scrolling should move back a page")

            for _ = 1, 20 do
                press(manager, "down")
            end
            h:assert_screen_contains(driver, "Page 5/5", "Down should reach max scroll offset page")

            press(manager, "down")
            h:assert_screen_contains(driver, "Page 5/5", "Down at end should clamp on max scroll offset page")

            press(manager, "b")
            h:assert_screen_contains(driver, "[A] Add Computer", "Back from ViewComputers should return to menu")
        end)
    end)

    h:test("screen flow: ViewComputers handles short viewport without page math errors", function()
        h:with_ui_driver(51, 8, function(driver)
            local ScreenManager = mpm("shelfos-swarm/ui/ScreenManager")
            local MainMenu = mpm("shelfos-swarm/screens/MainMenu")
            local ViewComputers = mpm("shelfos-swarm/screens/ViewComputers")

            local computers = {}
            for i = 1, 4 do
                computers[#computers + 1] = {
                    id = "compact_" .. i,
                    label = "Compact " .. i,
                    fingerprint = "FP-C-" .. i,
                    status = "active"
                }
            end

            local app = build_app_stub(computers)
            local manager = ScreenManager.new(app)
            manager.__driver = driver

            manager:push(MainMenu)
            manager:push(ViewComputers)

            h:assert_screen_contains(driver, "Computer Registry", "Title should render on short viewport")
            h:assert_screen_contains(driver, "Compact 1", "First entry should render on short viewport")

            press(manager, "down")
            h:assert_screen_contains(driver, "Compact 2", "Down should advance list safely with pageSize=1")
        end)
    end)
end
