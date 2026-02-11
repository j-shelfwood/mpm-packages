-- System.lua
-- Core system responsible for running displays with touch-based view cycling
-- Touch left side of monitor to go to previous view
-- Touch right side of monitor to go to next view
-- View selections are persisted to displays.config

local Config = mpm('displays/Config')

local this

-- Get list of available view names from manifest
local function getAvailableViews()
    local file = fs.open("/mpm/Packages/views/manifest.json", "r")
    if not file then
        return {}
    end
    local manifest = textutils.unserialiseJSON(file.readAll())
    file.close()

    local views = {}
    for _, filename in ipairs(manifest.files or {}) do
        -- Remove .lua extension
        local viewName = filename:gsub("%.lua$", "")
        table.insert(views, viewName)
    end
    return views
end

-- Filter views to only those that can mount (have required peripherals)
local function getMountableViews(allViews)
    local mountable = {}
    for _, viewName in ipairs(allViews) do
        local ok, ViewClass = pcall(mpm, 'views/' .. viewName)
        if ok and ViewClass and ViewClass.mount then
            local canMount = false
            local mountOk, mountResult = pcall(ViewClass.mount)
            if mountOk and mountResult then
                canMount = true
            end
            if canMount then
                table.insert(mountable, viewName)
            end
        end
    end
    return mountable
end

-- Get default config for a view (calls configure if available, uses empty table otherwise)
local function getDefaultConfig(ViewClass)
    -- Don't call configure() as it requires user input
    -- Just return empty config - views should handle missing config gracefully
    return {}
end

this = {
    -- Manage a single display with touch-based view cycling
    manageDisplay = function(display, availableViews)
        local monitor = peripheral.wrap(display.monitor)
        local monitorName = display.monitor

        if not monitor then
            print("Monitor not found: " .. monitorName)
            return
        end

        -- Find current view index in available views
        local currentIndex = 1
        for i, viewName in ipairs(availableViews) do
            if viewName == display.view then
                currentIndex = i
                break
            end
        end

        -- State
        local ViewClass = nil
        local viewInstance = nil
        local currentViewName = nil

        -- Load a view by index (persist=true saves to config)
        local function loadView(index, persist)
            -- Wrap index
            if index < 1 then
                index = #availableViews
            elseif index > #availableViews then
                index = 1
            end
            currentIndex = index

            local viewName = availableViews[currentIndex]
            if viewName == currentViewName and viewInstance then
                return -- Already loaded
            end

            print("Loading view: " .. viewName .. " on " .. monitorName)

            local ok, newViewClass = pcall(mpm, 'views/' .. viewName)
            if not ok then
                print("Error loading view: " .. tostring(newViewClass))
                return
            end

            ViewClass = newViewClass
            currentViewName = viewName

            -- Create new instance with default config
            local viewConfig = getDefaultConfig(ViewClass)
            local instanceOk, newInstance = pcall(ViewClass.new, monitor, viewConfig)
            if instanceOk then
                viewInstance = newInstance
                -- Persist view selection to config (only on user-initiated changes)
                if persist then
                    Config.updateDisplayView(monitorName, viewName)
                end
            else
                print("Error creating view instance: " .. tostring(newInstance))
                viewInstance = nil
            end

            -- Clear monitor before first render
            monitor.clear()
        end

        -- Initial load (don't persist - just loading from config)
        loadView(currentIndex, false)

        -- Show brief indicator of current view
        local function showViewIndicator()
            local width, height = monitor.getSize()
            local name = currentViewName or "Unknown"

            -- Save colors
            local bgColor = monitor.getBackgroundColor()
            local textColor = monitor.getTextColor()

            -- Draw indicator bar at top
            monitor.setBackgroundColor(colors.blue)
            monitor.setTextColor(colors.white)
            monitor.setCursorPos(1, 1)
            monitor.write(string.rep(" ", width))

            -- Center the view name with arrows
            local indicator = "< " .. name .. " >"
            local startX = math.floor((width - #indicator) / 2) + 1
            monitor.setCursorPos(startX, 1)
            monitor.write(indicator)

            -- Restore colors
            monitor.setBackgroundColor(bgColor)
            monitor.setTextColor(textColor)
        end

        -- Render loop with touch handling
        while true do
            -- Render current view
            if viewInstance and ViewClass and ViewClass.render then
                local status, err = pcall(ViewClass.render, viewInstance)
                if not status then
                    print("Error rendering " .. (currentViewName or "view") .. ": " .. tostring(err))
                end
            end

            -- Wait for either sleep time or touch event
            local sleepTime = (ViewClass and ViewClass.sleepTime) or 1
            local timer = os.startTimer(sleepTime)

            while true do
                local event, p1, p2, p3 = os.pullEvent()

                if event == "timer" and p1 == timer then
                    -- Sleep complete, continue render loop
                    break
                elseif event == "monitor_touch" and p1 == monitorName then
                    local touchX = p2
                    local width = monitor.getSize()
                    local halfWidth = width / 2

                    os.cancelTimer(timer)

                    if touchX <= halfWidth then
                        -- Left side - previous view (persist selection)
                        loadView(currentIndex - 1, true)
                    else
                        -- Right side - next view (persist selection)
                        loadView(currentIndex + 1, true)
                    end

                    -- Show indicator briefly
                    showViewIndicator()
                    sleep(1)
                    monitor.clear()

                    break
                end
            end
        end
    end,

    listenForCancel = function()
        while true do
            local event, key = os.pullEvent("key")
            if key == keys.q then
                print("Cancellation key pressed. Exiting...")
                os.exit()
            end
        end
    end,

    run = function()
        local config = mpm('displays/Config').load()

        if #config == 0 then
            print("No displays configured. Starting setup...")
            mpm('displays/Installer').run()
            config = mpm('displays/Config').load()

            if #config == 0 then
                print("No displays configured. Exiting.")
                return
            end
        end

        -- Get all available and mountable views
        print("Scanning available views...")
        local allViews = getAvailableViews()
        local mountableViews = getMountableViews(allViews)

        if #mountableViews == 0 then
            print("No views can be mounted (missing peripherals). Exiting.")
            return
        end

        print("Available views: " .. table.concat(mountableViews, ", "))
        print("")
        print("Touch left side of monitor for previous view")
        print("Touch right side of monitor for next view")
        print("Press 'q' to quit")
        print("")

        local tasks = {}
        for _, display in ipairs(config) do
            table.insert(tasks, function()
                this.manageDisplay(display, mountableViews)
            end)
        end

        table.insert(tasks, this.listenForCancel)

        parallel.waitForAll(table.unpack(tasks))
    end
}

return this
