-- System.lua
-- Display management system with touch-based view cycling
-- Refactored to use shared ui/ and view management components

local Config = mpm('displays/Config')
local TouchZones = mpm('ui/TouchZones')
local ViewManager = mpm('views/Manager')

local System = {}

-- Overlay timeout in seconds
local OVERLAY_TIMEOUT = 3

-- Create a wrapped monitor that reserves row 1 (top) and row H (bottom) for overlay
-- Views render to rows 2 to H-1 but think they're rendering to row 1+
local function createViewMonitor(monitor)
    local width, height = monitor.getSize()

    -- Create a proxy that offsets Y coordinates by 1
    local viewMonitor = {}

    -- Pass through most methods directly
    for key, value in pairs(monitor) do
        if type(value) == "function" then
            viewMonitor[key] = value
        end
    end

    -- Override size to hide row 1 and last row
    function viewMonitor.getSize()
        local w, h = monitor.getSize()
        return w, math.max(1, h - 2)  -- Reserve top and bottom rows
    end

    -- Override cursor position to offset Y by 1
    function viewMonitor.setCursorPos(x, y)
        monitor.setCursorPos(x, y + 1)
    end

    function viewMonitor.getCursorPos()
        local x, y = monitor.getCursorPos()
        return x, math.max(1, y - 1)
    end

    -- Override clear to only clear rows 2 to H-1
    function viewMonitor.clear()
        local w, h = monitor.getSize()
        local bg = monitor.getBackgroundColor()
        monitor.setBackgroundColor(colors.black)
        for row = 2, h - 1 do
            monitor.setCursorPos(1, row)
            monitor.write(string.rep(" ", w))
        end
        monitor.setBackgroundColor(bg)
    end

    -- Override clearLine to offset Y
    function viewMonitor.clearLine()
        local x, y = monitor.getCursorPos()
        local w = monitor.getSize()
        monitor.setCursorPos(1, y)
        monitor.write(string.rep(" ", w))
        monitor.setCursorPos(x, y)
    end

    -- Override scroll to only affect view area
    function viewMonitor.scroll(n)
        -- For simplicity, just clear the view area
        viewMonitor.clear()
    end

    return viewMonitor
end

-- Create a display manager for a single monitor
local function createDisplayManager(display, availableViews)
    local monitorName = display.monitor
    local monitor = peripheral.wrap(monitorName)

    if not monitor then
        print("[!] Monitor not found: " .. monitorName)
        return nil
    end

    -- Create view monitor (reserves row 1 for overlay)
    local viewMonitor = createViewMonitor(monitor)

    -- State
    local state = {
        monitor = monitor,           -- Real monitor (for overlay)
        viewMonitor = viewMonitor,   -- Offset monitor (for views)
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

        -- Create instance with viewMonitor (offset by 1 row for overlay)
        local config = display.config or {}
        local ok, instance = pcall(View.new, state.viewMonitor, config)

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

    -- Draw overlay bar on row 1 of the REAL monitor
    local function drawOverlay()
        local width = state.monitor.getSize()
        local name = state.currentViewName or "Unknown"
        local viewNum = state.currentIndex .. "/" .. #availableViews
        local indicator = "< " .. name .. " >"

        -- Draw overlay bar at row 1 (real monitor)
        state.monitor.setBackgroundColor(colors.blue)
        state.monitor.setTextColor(colors.white)
        state.monitor.setCursorPos(1, 1)
        state.monitor.write(string.rep(" ", width))

        -- Left arrow hint
        state.monitor.setCursorPos(1, 1)
        state.monitor.write(" <")

        -- Right arrow hint
        state.monitor.setCursorPos(width - 1, 1)
        state.monitor.write("> ")

        -- Centered view name
        local startX = math.floor((width - #indicator) / 2) + 1
        state.monitor.setCursorPos(startX, 1)
        state.monitor.write(indicator)

        -- View count on right (if room)
        if width > #indicator + 10 then
            state.monitor.setCursorPos(width - #viewNum, 1)
            state.monitor.write(viewNum)
        end

        -- Reset colors
        state.monitor.setBackgroundColor(colors.black)
        state.monitor.setTextColor(colors.white)
    end

    -- Clear overlay bar (row 1)
    local function clearOverlay()
        local width = state.monitor.getSize()
        state.monitor.setBackgroundColor(colors.black)
        state.monitor.setCursorPos(1, 1)
        state.monitor.write(string.rep(" ", width))
    end

    -- Show overlay and start/reset timeout
    local function showOverlay()
        state.overlayVisible = true
        state.lastInteraction = os.epoch("utc")
    end

    -- Hide overlay
    local function hideOverlay()
        state.overlayVisible = false
        clearOverlay()
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

    -- Initial setup: clear screen and load first view
    state.monitor.clear()
    loadView(state.currentIndex, false)

    -- Return manager interface
    return {
        state = state,

        render = function()
            -- Draw overlay first if visible (on row 1 of real monitor)
            -- This ensures it's always present even if view has issues
            if state.overlayVisible then
                drawOverlay()
            end

            -- Render view content (uses viewMonitor which is offset to row 2+)
            if state.viewInstance and state.viewClass and state.viewClass.render then
                local ok, err = pcall(state.viewClass.render, state.viewInstance)
                if not ok then
                    print("[!] Render error: " .. tostring(err))
                end
            end

            -- Redraw overlay after view render to ensure it's on top
            -- (view's clear() only affects rows 2+ now, but just in case)
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
