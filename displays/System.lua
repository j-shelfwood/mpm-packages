-- System.lua
-- Display management system with touch-based view cycling
-- Refactored to use shared ui/ and view management components

local Config = mpm('displays/Config')
local TouchZones = mpm('ui/TouchZones')
local ViewManager = mpm('views/Manager')

local System = {}

-- Create a display manager for a single monitor
local function createDisplayManager(display, availableViews)
    local monitorName = display.monitor
    local monitor = peripheral.wrap(monitorName)

    if not monitor then
        print("[!] Monitor not found: " .. monitorName)
        return nil
    end

    -- State
    local state = {
        monitor = monitor,
        monitorName = monitorName,
        currentIndex = 1,
        currentViewName = nil,
        viewClass = nil,
        viewInstance = nil,
        touchZones = TouchZones.new(monitor),
        showingIndicator = false
    }

    -- Find current view index
    for i, viewName in ipairs(availableViews) do
        if viewName == display.view then
            state.currentIndex = i
            break
        end
    end

    -- Load a view by index
    local function loadView(index, persist)
        -- Wrap index
        if index < 1 then
            index = #availableViews
        elseif index > #availableViews then
            index = 1
        end
        state.currentIndex = index

        local viewName = availableViews[index]
        if viewName == state.currentViewName and state.viewInstance then
            return true
        end

        print("[*] " .. monitorName .. " -> " .. viewName)

        -- Load view using ViewManager
        local View = ViewManager.load(viewName)
        if not View then
            print("[!] Failed to load: " .. viewName)
            return false
        end

        state.viewClass = View
        state.currentViewName = viewName

        -- Create instance
        local config = display.config or {}
        local ok, instance = pcall(View.new, monitor, config)

        if ok then
            state.viewInstance = instance

            -- Persist if requested
            if persist then
                Config.updateDisplayView(monitorName, viewName)
            end
        else
            print("[!] Instance error: " .. tostring(instance))
            state.viewInstance = nil
            return false
        end

        monitor.clear()
        return true
    end

    -- Show view indicator
    local function showIndicator()
        state.showingIndicator = true

        local width = monitor.getSize()
        local name = state.currentViewName or "Unknown"
        local indicator = "< " .. name .. " >"

        monitor.setBackgroundColor(colors.blue)
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(1, 1)
        monitor.write(string.rep(" ", width))

        local startX = math.floor((width - #indicator) / 2) + 1
        monitor.setCursorPos(startX, 1)
        monitor.write(indicator)

        monitor.setBackgroundColor(colors.black)
        monitor.setTextColor(colors.white)
    end

    -- Set up touch zones
    local width, height = monitor.getSize()
    local halfWidth = math.floor(width / 2)

    state.touchZones:addZone("prev", 1, 1, halfWidth, height, function()
        loadView(state.currentIndex - 1, true)
        showIndicator()
    end)

    state.touchZones:addZone("next", halfWidth + 1, 1, width, height, function()
        loadView(state.currentIndex + 1, true)
        showIndicator()
    end)

    -- Initial load
    loadView(state.currentIndex, false)

    -- Return manager interface
    return {
        state = state,

        render = function()
            if state.showingIndicator then
                return
            end

            if state.viewInstance and state.viewClass and state.viewClass.render then
                local ok, err = pcall(state.viewClass.render, state.viewInstance)
                if not ok then
                    print("[!] Render error: " .. tostring(err))
                end
            end
        end,

        handleTouch = function(touchMonitor, x, y)
            if touchMonitor ~= monitorName then
                return false
            end

            -- Clear indicator on any touch if showing
            if state.showingIndicator then
                state.showingIndicator = false
                monitor.clear()
                return true
            end

            return state.touchZones:handleTouch(touchMonitor, x, y)
        end,

        getSleepTime = function()
            return (state.viewClass and state.viewClass.sleepTime) or 1
        end,

        getMonitorName = function()
            return monitorName
        end
    }
end

-- Run a single display (blocking)
local function runDisplay(manager)
    while true do
        manager.render()

        local sleepTime = manager.getSleepTime()
        local timer = os.startTimer(sleepTime)

        while true do
            local event, p1, p2, p3 = os.pullEvent()

            if event == "timer" and p1 == timer then
                break
            elseif event == "monitor_touch" then
                if manager.handleTouch(p1, p2, p3) then
                    os.cancelTimer(timer)
                    sleep(1)  -- Brief pause after touch
                    break
                end
            end
        end
    end
end

-- Listen for quit key
local function listenForQuit()
    while true do
        local event, key = os.pullEvent("key")
        if key == keys.q then
            print("")
            print("[*] Quit requested")
            return
        end
    end
end

-- Main run function
function System.run()
    local config = Config.load()

    if #config == 0 then
        print("[!] No displays configured")
        print("    Run: mpm run displays/setup")
        return
    end

    -- Get mountable views
    print("[*] Scanning views...")
    local availableViews = ViewManager.getMountableViews()

    if #availableViews == 0 then
        print("[!] No views available")
        print("    Check peripheral connections")
        return
    end

    print("[*] Available: " .. table.concat(availableViews, ", "))
    print("")

    -- Create display managers
    local managers = {}
    for _, display in ipairs(config) do
        local manager = createDisplayManager(display, availableViews)
        if manager then
            table.insert(managers, manager)
        end
    end

    if #managers == 0 then
        print("[!] No monitors connected")
        return
    end

    print("")
    print("[*] Touch left/right to cycle views")
    print("[*] Press 'q' to quit")
    print("")

    -- Create parallel tasks
    local tasks = {}

    for _, manager in ipairs(managers) do
        table.insert(tasks, function()
            runDisplay(manager)
        end)
    end

    table.insert(tasks, listenForQuit)

    -- Run until quit
    parallel.waitForAny(table.unpack(tasks))

    -- Cleanup
    for _, manager in ipairs(managers) do
        local mon = peripheral.wrap(manager.getMonitorName())
        if mon then
            mon.setBackgroundColor(colors.black)
            mon.clear()
        end
    end

    print("[*] Goodbye!")
end

return System
