-- Monitor.lua
-- Single monitor management with settings-button pattern
-- Touch to show settings, click to open view selector

local ViewManager = mpm('shelfos/view/Manager')

local Monitor = {}
Monitor.__index = Monitor

-- Calculate optimal text scale based on monitor size
-- Returns scale that makes UI elements appropriately sized
local function calculateTextScale(width, height)
    -- CC:Tweaked supports 0.5 to 5 in 0.5 increments
    -- Larger monitors can use smaller scale for more content
    -- Smaller monitors need larger scale for readability

    local pixels = width * height

    if pixels >= 800 then
        return 1.0  -- Large monitor: normal scale
    elseif pixels >= 400 then
        return 1.0  -- Medium: normal scale
    elseif pixels >= 150 then
        return 0.5  -- Small: half scale for more room
    else
        return 0.5  -- Very small: minimum scale
    end
end

-- Create a new monitor manager
function Monitor.new(config, onViewChange)
    local self = setmetatable({}, Monitor)

    self.peripheralName = config.peripheral
    self.label = config.label or config.peripheral
    self.viewName = config.view
    self.viewConfig = config.viewConfig or {}
    self.onViewChange = onViewChange

    -- Try to connect
    self.peripheral = peripheral.wrap(self.peripheralName)
    self.connected = self.peripheral ~= nil

    if not self.connected then
        return self
    end

    -- State
    self.view = nil
    self.viewInstance = nil
    self.renderTimer = nil
    self.settingsTimer = nil
    self.showingSettings = false
    self.inConfigMenu = false
    self.availableViews = {}
    self.currentIndex = 1

    -- Initialize
    self:initialize()

    return self
end

-- Initialize the monitor
function Monitor:initialize()
    if not self.connected then return end

    -- Apply optimal text scale based on monitor size
    local width, height = self.peripheral.getSize()
    local scale = calculateTextScale(width, height)
    self.peripheral.setTextScale(scale)

    -- Re-get size after scale change (dimensions change with scale)
    width, height = self.peripheral.getSize()

    -- Get available views
    self.availableViews = ViewManager.getMountableViews()

    -- Find current view index
    for i, name in ipairs(self.availableViews) do
        if name == self.viewName then
            self.currentIndex = i
            break
        end
    end

    -- Load initial view
    self:loadView(self.viewName)
end

-- Load a view by name
function Monitor:loadView(viewName)
    if not self.connected then return false end

    local View = ViewManager.load(viewName)
    if not View then
        print("[Monitor] Failed to load: " .. viewName)
        return false
    end

    self.view = View
    self.viewName = viewName

    -- Update index
    for i, name in ipairs(self.availableViews) do
        if name == viewName then
            self.currentIndex = i
            break
        end
    end

    -- Create view instance
    local ok, instance = pcall(View.new, self.peripheral, self.viewConfig)
    if ok then
        self.viewInstance = instance
    else
        print("[Monitor] View error: " .. tostring(instance))
        self.viewInstance = nil
        return false
    end

    -- Clear and schedule render
    self.peripheral.clear()
    self:scheduleRender()

    return true
end

-- Draw settings button with padding
function Monitor:drawSettingsButton()
    local width, height = self.peripheral.getSize()

    -- Save state
    local oldBg = self.peripheral.getBackgroundColor()
    local oldFg = self.peripheral.getTextColor()

    -- Button with padding: " [*] " in bottom-right with 1 char margin
    local buttonText = " [*] "
    local buttonX = width - #buttonText - 1  -- 1 char padding from right edge
    local buttonY = height - 1               -- 1 row padding from bottom

    -- Ensure minimum position
    buttonX = math.max(1, buttonX)
    buttonY = math.max(1, buttonY)

    self.peripheral.setBackgroundColor(colors.blue)
    self.peripheral.setTextColor(colors.white)
    self.peripheral.setCursorPos(buttonX, buttonY)
    self.peripheral.write(buttonText)

    -- Restore
    self.peripheral.setBackgroundColor(oldBg)
    self.peripheral.setTextColor(oldFg)

    self.showingSettings = true
    self.settingsTimer = os.startTimer(3)

    -- Store button bounds for hit detection
    self.settingsButtonBounds = {
        x1 = buttonX,
        y1 = buttonY,
        x2 = buttonX + #buttonText - 1,
        y2 = buttonY
    }
end

-- Hide settings button
function Monitor:hideSettingsButton()
    self.showingSettings = false
    self.settingsTimer = nil
    self.settingsButtonBounds = nil
end

-- Check if touch is on settings button
function Monitor:isSettingsButtonTouch(x, y)
    if not self.settingsButtonBounds then return false end

    local b = self.settingsButtonBounds
    return x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2
end

-- Draw the configuration menu with proper scaling
function Monitor:drawConfigMenu()
    local width, height = self.peripheral.getSize()

    self.peripheral.setBackgroundColor(colors.black)
    self.peripheral.clear()

    -- Title bar with padding
    self.peripheral.setBackgroundColor(colors.blue)
    self.peripheral.setTextColor(colors.white)
    self.peripheral.setCursorPos(1, 1)
    self.peripheral.write(string.rep(" ", width))

    local title = "Select View"
    local titleX = math.max(1, math.floor((width - #title) / 2) + 1)
    self.peripheral.setCursorPos(titleX, 1)
    self.peripheral.write(title)

    -- View list with padding
    self.peripheral.setBackgroundColor(colors.black)
    local startY = 3
    local maxItems = math.max(1, height - 5)  -- Leave room for title, spacing, and cancel

    for i, viewName in ipairs(self.availableViews) do
        if i <= maxItems then
            local y = startY + i - 1
            local displayName = viewName

            -- Truncate if too long
            if #displayName > width - 4 then
                displayName = displayName:sub(1, width - 7) .. "..."
            end

            if i == self.currentIndex then
                -- Highlighted (current)
                self.peripheral.setBackgroundColor(colors.gray)
                self.peripheral.setTextColor(colors.white)
                self.peripheral.setCursorPos(1, y)
                self.peripheral.write(string.rep(" ", width))
                self.peripheral.setCursorPos(2, y)
                self.peripheral.write("> " .. displayName)
            else
                self.peripheral.setBackgroundColor(colors.black)
                self.peripheral.setTextColor(colors.lightGray)
                self.peripheral.setCursorPos(2, y)
                self.peripheral.write("  " .. displayName)
            end
        end
    end

    -- Cancel button at bottom with padding
    local cancelY = height
    self.peripheral.setBackgroundColor(colors.red)
    self.peripheral.setTextColor(colors.white)
    self.peripheral.setCursorPos(1, cancelY)
    self.peripheral.write(string.rep(" ", width))

    local cancelText = " Cancel "
    local cancelX = math.max(1, math.floor((width - #cancelText) / 2) + 1)
    self.peripheral.setCursorPos(cancelX, cancelY)
    self.peripheral.write(cancelText)

    -- Reset colors
    self.peripheral.setBackgroundColor(colors.black)
    self.peripheral.setTextColor(colors.white)

    -- Store menu bounds
    self.menuStartY = startY
    self.menuMaxItems = maxItems
    self.menuCancelY = cancelY
end

-- Handle touch in config menu
function Monitor:handleConfigMenuTouch(x, y)
    -- Cancel button
    if y == self.menuCancelY then
        return "cancel"
    end

    -- View selection
    local touchedIndex = y - self.menuStartY + 1
    if touchedIndex >= 1 and touchedIndex <= #self.availableViews and touchedIndex <= self.menuMaxItems then
        return self.availableViews[touchedIndex]
    end

    return nil
end

-- Open config menu
function Monitor:openConfigMenu()
    self.inConfigMenu = true
    self.showingSettings = false

    -- Cancel pending timers
    if self.renderTimer then
        os.cancelTimer(self.renderTimer)
        self.renderTimer = nil
    end
    if self.settingsTimer then
        os.cancelTimer(self.settingsTimer)
        self.settingsTimer = nil
    end

    self:drawConfigMenu()
end

-- Close config menu
function Monitor:closeConfigMenu()
    self.inConfigMenu = false
    self.peripheral.clear()
    self:scheduleRender()
end

-- Render the view
function Monitor:render()
    if self.inConfigMenu or not self.viewInstance then
        return
    end

    local ok, err = pcall(self.view.render, self.viewInstance)
    if not ok then
        self.peripheral.setCursorPos(1, 1)
        self.peripheral.setTextColor(colors.red)
        self.peripheral.write("Error")
        self.peripheral.setTextColor(colors.white)
    end

    -- Redraw settings button if showing
    if self.showingSettings then
        self:drawSettingsButton()
    end
end

-- Schedule next render
function Monitor:scheduleRender()
    if self.inConfigMenu then return end
    local sleepTime = (self.view and self.view.sleepTime) or 1
    self.renderTimer = os.startTimer(sleepTime)
end

-- Handle touch event
function Monitor:handleTouch(monitorName, x, y)
    if monitorName ~= self.peripheralName then
        return false
    end

    -- Config menu mode
    if self.inConfigMenu then
        local result = self:handleConfigMenuTouch(x, y)

        if result == "cancel" then
            self:closeConfigMenu()
        elseif result then
            -- Selected a view
            if self.onViewChange then
                self.onViewChange(self.peripheralName, result)
            end
            self:loadView(result)
            self:closeConfigMenu()
        end

        return true
    end

    -- Check for settings button click
    if self.showingSettings and self:isSettingsButtonTouch(x, y) then
        self:openConfigMenu()
        return true
    end

    -- Any other touch: show settings button
    self:drawSettingsButton()
    return true
end

-- Handle timer event
function Monitor:handleTimer(timerId)
    if timerId == self.settingsTimer then
        self:hideSettingsButton()
        return true
    elseif timerId == self.renderTimer then
        self:render()
        self:scheduleRender()
        return true
    end
    return false
end

-- Check if this is our render timer (for Kernel compatibility)
function Monitor:isRenderTimer(timerId)
    return timerId == self.renderTimer or timerId == self.settingsTimer
end

-- Clear the monitor
function Monitor:clear()
    if self.connected then
        self.peripheral.setBackgroundColor(colors.black)
        self.peripheral.clear()
    end
end

-- Check if monitor is connected
function Monitor:isConnected()
    return self.connected
end

-- Get monitor name
function Monitor:getName()
    return self.label
end

-- Get peripheral name
function Monitor:getPeripheralName()
    return self.peripheralName
end

-- Get current view name
function Monitor:getViewName()
    return self.viewName or "none"
end

-- Get view configuration
function Monitor:getViewConfig()
    return self.viewConfig
end

-- Update view configuration
function Monitor:setViewConfig(key, value)
    self.viewConfig[key] = value

    if self.viewInstance and self.view and self.view.onConfigChange then
        pcall(self.view.onConfigChange, self.viewInstance, key, value)
    end
end

-- Reconnect to peripheral
function Monitor:reconnect()
    self.peripheral = peripheral.wrap(self.peripheralName)
    self.connected = self.peripheral ~= nil

    if self.connected then
        self:initialize()
    end

    return self.connected
end

return Monitor
