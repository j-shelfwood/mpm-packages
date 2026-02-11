-- System.lua
-- Display management system with touch-based view cycling
-- Refactored to use shared ui/ and view management components

local Config = mpm('displays/Config')
local TouchZones = mpm('ui/TouchZones')
local ViewManager = mpm('views/Manager')

local System = {}

-- Overlay timeout in seconds
local OVERLAY_TIMEOUT = 3

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
        overlayVisible = false,
        overlayTimer = nil,
        lastInteraction = 0
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

        return true
    end

    -- Draw overlay on top of current view
    local function drawOverlay()
        local width = monitor.getSize()
        local name = state.currentViewName or "Unknown"
        local viewNum = state.currentIndex .. "/" .. #availableViews
        local indicator = "< " .. name .. " >"

        -- Save current colors
        local prevBg = monitor.getBackgroundColor()
        local prevFg = monitor.getTextColor()

        -- Draw overlay bar at top
        monitor.setBackgroundColor(colors.blue)
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(1, 1)
        monitor.write(string.rep(" ", width))

        -- Left arrow hint
        monitor.setCursorPos(1, 1)
        monitor.write(" <")

        -- Right arrow hint
        monitor.setCursorPos(width - 1, 1)
        monitor.write("> ")

        -- Centered view name
        local startX = math.floor((width - #indicator) / 2) + 1
        monitor.setCursorPos(startX, 1)
        monitor.write(indicator)

        -- View count on right (if room)
        if width > #indicator + 10 then
            monitor.setCursorPos(width - #viewNum, 1)
            monitor.write(viewNum)
        end

        -- Restore colors
        monitor.setBackgroundColor(prevBg)
        monitor.setTextColor(prevFg)
    end

    -- Show overlay and start/reset timeout
    local function showOverlay()
        state.overlayVisible = true
        state.lastInteraction = os.epoch("utc")
    end

    -- Hide overlay
    local function hideOverlay()
        state.overlayVisible = false
    end

    -- Check if overlay should auto-hide
    local function checkOverlayTimeout()
        if state.overlayVisible then
            local elapsed = (os.epoch("utc") - state.lastInteraction) / 1000
            if elapsed >= OVERLAY_TIMEOUT then
                hideOverlay()
                return true  -- Overlay was hidden
            end
        end
        return false
    end

    -- Set up touch zones for navigation
    local width, height = monitor.getSize()
    local halfWidth = math.floor(width / 2)

    state.touchZones:addZone("prev", 1, 1, halfWidth, height, function()
        loadView(state.currentIndex - 1, true)
        showOverlay()  -- Keep/refresh overlay after switch
    end)

    state.touchZones:addZone("next", halfWidth + 1, 1, width, height, function()
        loadView(state.currentIndex + 1, true)
        showOverlay()  -- Keep/refresh overlay after switch
    end)

    -- Initial load
    loadView(state.currentIndex, false)

    -- Return manager interface
    return {
        state = state,

        render = function()
            -- Always render the view content first
            if state.viewInstance and state.viewClass and state.viewClass.render then
                local ok, err = pcall(state.viewClass.render, state.viewInstance)
                if not ok then
                    print("[!] Render error: " .. tostring(err))
                end
            end

            -- Then draw overlay on top if visible
            if state.overlayVisible then
                drawOverlay()
            end
        end,

        handleTouch = function(touchMonitor, x, y)
            if touchMonitor ~= monitorName then
                return false
            end

            -- First touch when overlay not visible: just show overlay
            if not state.overlayVisible then
                showOverlay()
                return true
            end

            -- Overlay is visible: process touch zones (left/right navigation)
            state.lastInteraction = os.epoch("utc")
            return state.touchZones:handleTouch(touchMonitor, x, y)
        end,

        checkTimeout = function()
            return checkOverlayTimeout()
        end,

        getSleepTime = function()
            -- Use shorter sleep when overlay visible for responsive timeout
            if state.overlayVisible then
                return 0.5
            end
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

        -- Check overlay timeout
        manager.checkTimeout()

        local sleepTime = manager.getSleepTime()
        local timer = os.startTimer(sleepTime)

        while true do
            local event, p1, p2, p3 = os.pullEvent()

            if event == "timer" and p1 == timer then
                break
            elseif event == "monitor_touch" then
                if manager.handleTouch(p1, p2, p3) then
                    os.cancelTimer(timer)
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

    -- Debug: show all views and their mount status
    local allViews = ViewManager.getAvailableViews()
    print("[*] Found " .. #allViews .. " views in manifest")

    for _, viewName in ipairs(allViews) do
        local View = ViewManager.load(viewName)
        if not View then
            print("    [!] " .. viewName .. ": LOAD FAILED")
        elseif not View.mount then
            print("    [+] " .. viewName .. ": OK (no mount check)")
        else
            local ok, canMount = pcall(View.mount)
            if not ok then
                print("    [!] " .. viewName .. ": MOUNT ERROR - " .. tostring(canMount))
            elseif canMount then
                print("    [+] " .. viewName .. ": OK")
            else
                print("    [-] " .. viewName .. ": skipped (peripheral missing)")
            end
        end
    end

    local availableViews = ViewManager.getMountableViews()

    if #availableViews == 0 then
        print("[!] No views available")
        print("    Check peripheral connections")
        return
    end

    print("")
    print("[*] Active: " .. table.concat(availableViews, ", "))
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
