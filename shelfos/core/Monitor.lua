-- Monitor.lua
-- Single monitor management with view lifecycle and touch handling

local TouchZones = mpm('ui/TouchZones')
local ViewManager = mpm('shelfos/view/Manager')

local Monitor = {}
Monitor.__index = Monitor

-- Create a new monitor manager
-- @param config Monitor configuration from shelfos.config
function Monitor.new(config)
    local self = setmetatable({}, Monitor)

    self.peripheralName = config.peripheral
    self.label = config.label or config.peripheral
    self.viewName = config.view
    self.viewConfig = config.viewConfig or {}

    -- Try to connect
    self.peripheral = peripheral.wrap(self.peripheralName)
    self.connected = self.peripheral ~= nil

    -- State
    self.view = nil
    self.viewInstance = nil
    self.touchZones = nil
    self.configMode = false
    self.renderTimer = nil
    self.initialized = false
    self.showingIndicator = false

    -- Initialize if connected
    if self.connected then
        self:initialize()
    end

    return self
end

-- Initialize the monitor
function Monitor:initialize()
    if not self.connected then return end

    -- Set up touch zones
    self.touchZones = TouchZones.new(self.peripheral)
    self:setupTouchZones()

    -- Load initial view
    self:loadView(self.viewName)

    self.initialized = true
end

-- Set up default touch zones
function Monitor:setupTouchZones()
    local width, height = self.peripheral.getSize()
    local halfWidth = math.floor(width / 2)

    -- Left half: previous view
    self.touchZones:addZone("prev", 1, 1, halfWidth, height - 1, function()
        self:previousView()
    end)

    -- Right half: next view
    self.touchZones:addZone("next", halfWidth + 1, 1, width, height - 1, function()
        self:nextView()
    end)

    -- Bottom row: config mode
    self.touchZones:addZone("config", 1, height, width, height, function()
        self:toggleConfigMode()
    end)
end

-- Load a view by name
function Monitor:loadView(viewName)
    if not self.connected then return false end

    local View = ViewManager.load(viewName)
    if not View then
        print("[Monitor] Failed to load view: " .. viewName)
        return false
    end

    self.view = View
    self.viewName = viewName

    -- Create view instance
    local ok, instance = pcall(View.new, self.peripheral, self.viewConfig)
    if ok then
        self.viewInstance = instance
    else
        print("[Monitor] Failed to create view instance: " .. tostring(instance))
        self.viewInstance = nil
        return false
    end

    -- Clear for fresh start
    self.peripheral.clear()

    -- Schedule first render
    self:scheduleRender()

    return true
end

-- Cycle to next view
function Monitor:nextView()
    local views = ViewManager.getMountableViews()
    if #views == 0 then return end

    local currentIndex = 1
    for i, name in ipairs(views) do
        if name == self.viewName then
            currentIndex = i
            break
        end
    end

    local nextIndex = currentIndex + 1
    if nextIndex > #views then
        nextIndex = 1
    end

    self:loadView(views[nextIndex])
    self:showIndicator()
end

-- Cycle to previous view
function Monitor:previousView()
    local views = ViewManager.getMountableViews()
    if #views == 0 then return end

    local currentIndex = 1
    for i, name in ipairs(views) do
        if name == self.viewName then
            currentIndex = i
            break
        end
    end

    local prevIndex = currentIndex - 1
    if prevIndex < 1 then
        prevIndex = #views
    end

    self:loadView(views[prevIndex])
    self:showIndicator()
end

-- Show view name indicator briefly
function Monitor:showIndicator()
    if not self.connected then return end

    self.showingIndicator = true

    local width = self.peripheral.getSize()
    local indicator = "< " .. self.viewName .. " >"

    -- Draw indicator bar
    self.peripheral.setBackgroundColor(colors.blue)
    self.peripheral.setTextColor(colors.white)
    self.peripheral.setCursorPos(1, 1)
    self.peripheral.write(string.rep(" ", width))

    local startX = math.floor((width - #indicator) / 2) + 1
    self.peripheral.setCursorPos(startX, 1)
    self.peripheral.write(indicator)

    self.peripheral.setBackgroundColor(colors.black)
    self.peripheral.setTextColor(colors.white)

    -- Clear indicator after delay
    os.startTimer(1.5)
end

-- Toggle configuration mode
function Monitor:toggleConfigMode()
    self.configMode = not self.configMode

    if self.configMode then
        self:showConfigOverlay()
    else
        self.peripheral.clear()
        self:render()
    end
end

-- Show configuration overlay
function Monitor:showConfigOverlay()
    -- Get view's config schema
    local schema = {}
    if self.view and self.view.configSchema then
        schema = self.view.configSchema
    end

    if #schema == 0 then
        -- No config options, show message
        local width, height = self.peripheral.getSize()
        self.peripheral.setBackgroundColor(colors.gray)
        self.peripheral.clear()
        self.peripheral.setTextColor(colors.white)
        self.peripheral.setCursorPos(2, 2)
        self.peripheral.write("No config options")
        self.peripheral.setCursorPos(2, 4)
        self.peripheral.write("Touch to close")
        return
    end

    -- TODO: Implement full config UI with widgets
    -- For now, just show placeholder
    local ConfigMode = mpm('shelfos/input/ConfigMode')
    ConfigMode.show(self, schema, self.viewConfig)
end

-- Handle touch event
function Monitor:handleTouch(monitorName, x, y)
    if monitorName ~= self.peripheralName then
        return false
    end

    -- Clear indicator if showing
    if self.showingIndicator then
        self.showingIndicator = false
        self.peripheral.clear()
        self:render()
        return true
    end

    -- Route to touch zones
    if self.touchZones then
        return self.touchZones:handleTouch(monitorName, x, y)
    end

    return false
end

-- Render the current view
function Monitor:render()
    if not self.connected or not self.viewInstance or self.configMode then
        return
    end

    if self.showingIndicator then
        return  -- Don't render over indicator
    end

    local ok, err = pcall(self.view.render, self.viewInstance)
    if not ok then
        self.peripheral.setBackgroundColor(colors.black)
        self.peripheral.setTextColor(colors.red)
        self.peripheral.setCursorPos(1, 1)
        self.peripheral.write("Render error")
        self.peripheral.setCursorPos(1, 2)
        self.peripheral.write(tostring(err):sub(1, 20))
    end
end

-- Schedule next render
function Monitor:scheduleRender()
    local sleepTime = 1
    if self.view and self.view.sleepTime then
        sleepTime = self.view.sleepTime
    end

    self.renderTimer = os.startTimer(sleepTime)
end

-- Check if timer is our render timer
function Monitor:isRenderTimer(timerId)
    return timerId == self.renderTimer
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

    -- Notify view if it supports config changes
    if self.viewInstance and self.view.onConfigChange then
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
