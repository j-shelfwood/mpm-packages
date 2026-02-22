-- Monitor.lua
-- Monitor facade that coordinates focused monitor subsystems.

local ViewManager = mpm('views/Manager')

local MonitorBuffer = mpm('shelfos/core/MonitorBuffer')
local MonitorRenderer = mpm('shelfos/core/MonitorRenderer')
local MonitorTouch = mpm('shelfos/core/MonitorTouch')
local MonitorConfigFlow = mpm('shelfos/core/MonitorConfigFlow')
local MonitorLifecycle = mpm('shelfos/core/MonitorLifecycle')

local Monitor = {}
Monitor.__index = Monitor

local function copyArray(arr)
    local copy = {}
    for i, v in ipairs(arr or {}) do
        copy[i] = v
    end
    return copy
end

function Monitor.new(config, onViewChange, settings, index, availableViews)
    local self = setmetatable({}, Monitor)

    self.peripheralName = config.peripheral
    self.label = config.label or config.peripheral
    self.viewName = config.view
    self.viewConfig = config.viewConfig or {}
    self.onViewChange = onViewChange
    self.themeName = (settings and settings.theme) or "default"
    self.index = index or 0
    self.renderPhase = self.index * 0.05

    self.view = nil
    self.viewInstance = nil
    self.renderTimer = nil
    self.loadRetryTimer = nil
    self.settingsTimer = nil
    self.showingSettings = false
    self.inConfigMenu = false
    self.availableViews = copyArray(availableViews)
    self.currentIndex = 1
    self.settingsButton = nil
    self.pairingMode = false
    self.touchDebounceUntil = 0
    self.lastLoadError = nil
    self.lastHealthCheckAt = 0
    self.healthCheckIntervalMs = 5000

    self.buffer = nil
    self.bufferWidth = 0
    self.bufferHeight = 0
    self.currentScale = 1.0

    self.peripheral = peripheral.wrap(self.peripheralName)
    self.connected = self.peripheral ~= nil
    if self.connected then
        self:initialize()
    end

    return self
end

function Monitor:scheduleLoadRetry(delaySeconds)
    MonitorLifecycle.scheduleLoadRetry(self, delaySeconds)
end

function Monitor:scheduleRender(offset)
    MonitorLifecycle.scheduleRender(self, offset)
end

function Monitor:cancelTimers()
    MonitorLifecycle.cancelTimers(self)
end

function Monitor:initialize()
    if not self.connected then
        return
    end

    MonitorBuffer.initialize(self)

    if #self.availableViews == 0 then
        self.availableViews = ViewManager.getSelectableViews()
    end

    for i, name in ipairs(self.availableViews) do
        if name == self.viewName then
            self.currentIndex = i
            break
        end
    end

    self:loadView(self.viewName)
end

function Monitor:handleResize()
    MonitorBuffer.handleResize(self)
end

function Monitor:loadView(viewName)
    if not self.connected then
        return false
    end

    local requestedView = viewName or self.viewName or "Clock"

    local function tryLoad(name, config)
        local View = ViewManager.load(name)
        if not View then
            return false, "View not found: " .. tostring(name)
        end

        local ok, instance = pcall(View.new, self.buffer, config or {}, self.peripheralName)
        if not ok then
            return false, tostring(instance)
        end

        self.view = View
        self.viewName = name
        self.viewConfig = config or {}
        self.viewInstance = instance
        self.lastLoadError = nil

        for i, available in ipairs(self.availableViews) do
            if available == name then
                self.currentIndex = i
                break
            end
        end

        return true, nil
    end

    local ok, err = tryLoad(requestedView, self.viewConfig)

    if not ok and requestedView ~= "Clock" then
        print("[Monitor] Failed to load " .. tostring(requestedView) .. " on " .. (self.peripheralName or "unknown") .. ": " .. tostring(err))
        local fallbackConfig = ViewManager.getDefaultConfig("Clock")
        ok, err = tryLoad("Clock", fallbackConfig)
        if ok then
            print("[Monitor] Fallback view Clock loaded on " .. (self.peripheralName or "unknown"))
        end
    end

    if not ok then
        self.view = nil
        self.viewInstance = nil
        self.lastLoadError = tostring(err)
        print("[Monitor] View error on " .. (self.peripheralName or "unknown") .. ": " .. self.lastLoadError)
        self:scheduleLoadRetry(2)
        return false
    end

    self:render()
    self:scheduleRender(self.renderPhase)

    return true
end

function Monitor:drawSettingsButton()
    MonitorTouch.drawSettingsButton(self)
end

function Monitor:hideSettingsButton()
    MonitorTouch.hideSettingsButton(self)
end

function Monitor:isSettingsButtonTouch(x, y)
    return MonitorTouch.isSettingsButtonTouch(self, x, y)
end

function Monitor:openConfigMenu()
    MonitorConfigFlow.openConfigMenu(self)
end

function Monitor:closeConfigMenu(skipImmediateRender)
    local _ = skipImmediateRender
    MonitorConfigFlow.closeConfigMenu(self)
end

function Monitor:render()
    MonitorRenderer.render(self)
end

function Monitor:drawDependencyStatus(contextKey)
    MonitorRenderer.drawDependencyStatus(self, contextKey)
end

function Monitor:handleTouch(monitorName, x, y)
    return MonitorTouch.handleTouch(self, monitorName, x, y)
end

function Monitor:handleTimer(timerId)
    return MonitorLifecycle.handleTimer(self, timerId)
end

function Monitor:isRenderTimer(timerId)
    return timerId == self.renderTimer
        or timerId == self.settingsTimer
        or timerId == self.loadRetryTimer
end

function Monitor:clear()
    MonitorLifecycle.clear(self)
end

function Monitor:disconnect()
    MonitorLifecycle.disconnect(self)
end

function Monitor:isConnected()
    return self.connected
end

function Monitor:getName()
    return self.label
end

function Monitor:getPeripheralName()
    return self.peripheralName
end

function Monitor:getViewName()
    return self.viewName or "none"
end

function Monitor:getViewConfig()
    return self.viewConfig
end

function Monitor:setViewConfig(key, value)
    self.viewConfig[key] = value

    if self.viewInstance and self.view and self.view.onConfigChange then
        pcall(self.view.onConfigChange, self.viewInstance, key, value)
    end
end

function Monitor:reconnect()
    return MonitorLifecycle.reconnect(self)
end

function Monitor:adoptPeripheralName(newPeripheralName)
    return MonitorLifecycle.adoptPeripheralName(self, newPeripheralName)
end

function Monitor:setTheme(themeName)
    self.themeName = themeName or "default"
    MonitorBuffer.applyTheme(self)

    if self.connected and not self.inConfigMenu and self.viewInstance then
        self:render()
    end
end

function Monitor:getTheme()
    return self.themeName
end

function Monitor:setPairingMode(enabled)
    self.pairingMode = enabled
end

function Monitor:runLoop(running)
    MonitorLifecycle.runLoop(self, running)
end

return Monitor
