-- Monitor.lua
-- Single monitor management with settings-button pattern
-- Touch to show settings, click to open view selector
-- Supports view configuration via configSchema
-- Now uses ui/ widgets for consistent styling

local ViewManager = mpm('views/Manager')
local ConfigUI = mpm('shelfos/core/ConfigUI')
local Theme = mpm('utils/Theme')
local Core = mpm('ui/Core')
local Button = mpm('ui/Button')
local List = mpm('ui/List')

local Monitor = {}
Monitor.__index = Monitor

-- Calculate optimal text scale based on NATIVE monitor size (at scale 1.0)
-- This prevents feedback loops where changing scale changes dimensions
-- @param monitor The monitor peripheral
-- @return scale The calculated text scale
local function calculateTextScale(monitor)
    -- Get dimensions at native scale to determine physical monitor size
    local currentScale = monitor.getTextScale()
    monitor.setTextScale(1.0)
    local nativeWidth, nativeHeight = monitor.getSize()

    -- Calculate scale based on native (physical) dimensions
    -- A 2x2 monitor block is ~14x9 at scale 1.0
    -- A 3x3 monitor block is ~29x19 at scale 1.0
    -- A 4x4 monitor block is ~36x25 at scale 1.0
    local pixels = nativeWidth * nativeHeight

    local scale
    if pixels >= 400 then
        scale = 1.0  -- 3x3 or larger: normal scale
    else
        scale = 1.0  -- 2x2 or smaller: keep scale 1.0 for readability
        -- Note: Using 0.5 on small monitors causes text to be too small
    end

    -- Restore to calculated scale (or current if unchanged)
    if scale ~= 1.0 then
        monitor.setTextScale(scale)
    end
    -- If scale is 1.0, we already set it above

    return scale
end

-- Create a new monitor manager
-- @param config Monitor configuration from shelfos.config
-- @param onViewChange Callback for view changes
-- @param settings Global settings
-- @param index Monitor index (0-based) for staggering timers
function Monitor.new(config, onViewChange, settings, index)
    local self = setmetatable({}, Monitor)

    self.peripheralName = config.peripheral
    self.label = config.label or config.peripheral
    self.viewName = config.view
    self.viewConfig = config.viewConfig or {}
    self.onViewChange = onViewChange
    self.themeName = (settings and settings.theme) or "default"
    self.index = index or 0  -- Used for staggering render timers

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
    self.settingsButton = nil

    -- Initialize
    self:initialize()

    return self
end

-- Initialize the monitor
function Monitor:initialize()
    if not self.connected then return end

    -- Apply optimal text scale based on physical monitor size
    -- calculateTextScale handles getting native dimensions internally
    self.currentScale = calculateTextScale(self.peripheral)

    -- Apply theme palette
    Theme.apply(self.peripheral, self.themeName)

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

-- Handle monitor resize event (blocks added/removed)
function Monitor:handleResize()
    if not self.connected then return end

    -- Guard against resize loops from setTextScale
    if self.handlingResize then return end
    self.handlingResize = true

    -- Recalculate optimal text scale (uses native dimensions internally)
    self.currentScale = calculateTextScale(self.peripheral)

    -- Reapply theme (palette persists but good practice)
    Theme.apply(self.peripheral, self.themeName)

    -- Clear and re-render
    self.peripheral.clear()

    -- Reload view to recalculate layout
    if self.viewName then
        self:loadView(self.viewName)
    end

    self.handlingResize = false
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

    -- Clear, render immediately, then schedule next render
    -- Stagger initial timer by monitor index to prevent all monitors
    -- from rendering simultaneously (causes visual flashing)
    self.peripheral.clear()
    self:render()
    self:scheduleRender(self.index * 0.05)  -- 50ms stagger per monitor

    return true
end

-- Draw settings button using ui/Button
function Monitor:drawSettingsButton()
    local width, height = self.peripheral.getSize()

    -- Button in bottom-right with padding
    local buttonLabel = "[*]"
    local buttonX = width - #buttonLabel - 2  -- padding from edge
    local buttonY = height - 1                 -- 1 row padding from bottom

    -- Ensure minimum position
    buttonX = math.max(1, buttonX)
    buttonY = math.max(1, buttonY)

    -- Create button using ui/Button
    self.settingsButton = Button.neutral(self.peripheral, buttonX, buttonY, buttonLabel, nil, {
        padding = 1
    })
    self.settingsButton:render()

    self.showingSettings = true
    self.settingsTimer = os.startTimer(3)
end

-- Hide settings button
function Monitor:hideSettingsButton()
    self.showingSettings = false
    self.settingsTimer = nil
    self.settingsButton = nil
end

-- Check if touch is on settings button
function Monitor:isSettingsButtonTouch(x, y)
    if not self.settingsButton then return false end
    return self.settingsButton:contains(x, y)
end

-- Draw the configuration menu using ui/List
function Monitor:drawConfigMenu()
    -- Use ui/List for view selection
    local List = mpm('ui/List')

    local selected = List.new(self.peripheral, self.availableViews, {
        title = "Select View",
        selected = self.viewName,
        cancelText = "Cancel",
        formatFn = function(viewName)
            return viewName
        end
    }):show()

    return selected
end

-- Open config menu
function Monitor:openConfigMenu()
    self.inConfigMenu = true
    self.showingSettings = false
    self.settingsButton = nil

    -- Cancel pending timers
    if self.renderTimer then
        os.cancelTimer(self.renderTimer)
        self.renderTimer = nil
    end
    if self.settingsTimer then
        os.cancelTimer(self.settingsTimer)
        self.settingsTimer = nil
    end

    -- Show view selector
    local selectedView = self:drawConfigMenu()

    if selectedView and selectedView ~= "cancel" then
        -- Check if view has configSchema
        local View = ViewManager.load(selectedView)

        if View and View.configSchema and #View.configSchema > 0 then
            -- Show config menu for this view
            local newConfig = ConfigUI.drawConfigMenu(
                self.peripheral,
                selectedView,
                View.configSchema,
                self.viewConfig
            )

            if newConfig then
                -- User saved config
                self.viewConfig = newConfig
                if self.onViewChange then
                    self.onViewChange(self.peripheralName, selectedView, newConfig)
                end
                self:loadView(selectedView)
            end
            -- If cancelled, just close menu (don't change view)
        else
            -- No config needed - just load view
            self.viewConfig = {}
            if self.onViewChange then
                self.onViewChange(self.peripheralName, selectedView, {})
            end
            self:loadView(selectedView)
        end
    end

    self:closeConfigMenu()
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
-- @param offset Optional time offset to stagger initial renders (default 0)
function Monitor:scheduleRender(offset)
    if self.inConfigMenu then return end
    local sleepTime = (self.view and self.view.sleepTime) or 1
    self.renderTimer = os.startTimer(sleepTime + (offset or 0))
end

-- Handle touch event
function Monitor:handleTouch(monitorName, x, y)
    if monitorName ~= self.peripheralName then
        return false
    end

    -- Config menu is now handled synchronously in openConfigMenu
    if self.inConfigMenu then
        return false
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
        Core.clear(self.peripheral)
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

-- Set theme for this monitor
function Monitor:setTheme(themeName)
    self.themeName = themeName or "default"
    if self.connected then
        Theme.apply(self.peripheral, self.themeName)
        -- Re-render to show updated colors
        if not self.inConfigMenu and self.viewInstance then
            self:render()
        end
    end
end

-- Get current theme name
function Monitor:getTheme()
    return self.themeName
end

return Monitor
