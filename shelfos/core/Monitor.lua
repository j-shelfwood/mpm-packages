-- Monitor.lua
-- Monitor facade and lifecycle coordinator.

local ViewManager = mpm('views/Manager')
local MonitorConfigMenu = mpm('shelfos/core/MonitorConfigMenu')
local Core = mpm('ui/Core')
local EventLoop = mpm('ui/EventLoop')

local MonitorBuffer = mpm('shelfos/core/MonitorBuffer')
local MonitorRenderer = mpm('shelfos/core/MonitorRenderer')
local MonitorTouch = mpm('shelfos/core/MonitorTouch')

local Monitor = {}
Monitor.__index = Monitor

local TOUCH_DEBOUNCE_MS = 350
local CONFIG_EXIT_TOUCH_GUARD_MS = 700

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
    if self.inConfigMenu then
        return
    end

    if self.loadRetryTimer then
        os.cancelTimer(self.loadRetryTimer)
    end

    self.loadRetryTimer = os.startTimer(delaySeconds or 2)
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
    if self.inConfigMenu then
        return
    end

    self.touchDebounceUntil = os.epoch("utc") + TOUCH_DEBOUNCE_MS
    EventLoop.armTouchGuard(self.peripheralName, TOUCH_DEBOUNCE_MS)
    EventLoop.drainMonitorTouches(self.peripheralName, 8)
    self.inConfigMenu = true
    self.showingSettings = false
    self.settingsButton = nil

    if self.renderTimer then
        os.cancelTimer(self.renderTimer)
        self.renderTimer = nil
    end
    if self.loadRetryTimer then
        os.cancelTimer(self.loadRetryTimer)
        self.loadRetryTimer = nil
    end
    if self.settingsTimer then
        os.cancelTimer(self.settingsTimer)
        self.settingsTimer = nil
    end

    if self.buffer then
        self.buffer.setVisible(false)
    end

    local ok, selectedView, newConfig = pcall(MonitorConfigMenu.openConfigFlow, self)
    local didLoadView = false

    if not ok then
        print("[Monitor] Config menu error on " .. (self.peripheralName or "unknown") .. ": " .. tostring(selectedView))
    elseif selectedView then
        local pendingConfig = newConfig or {}
        local previousConfig = self.viewConfig
        self.viewConfig = pendingConfig
        didLoadView = self:loadView(selectedView) and true or false
        if didLoadView and self.onViewChange then
            self.onViewChange(self.peripheralName, selectedView, self.viewConfig)
        elseif not didLoadView then
            self.viewConfig = previousConfig
        end
    end

    self:closeConfigMenu(didLoadView)
end

function Monitor:closeConfigMenu(_skipImmediateRender)
    self.inConfigMenu = false
    self.touchDebounceUntil = os.epoch("utc") + CONFIG_EXIT_TOUCH_GUARD_MS
    EventLoop.armTouchGuard(self.peripheralName, CONFIG_EXIT_TOUCH_GUARD_MS)
    EventLoop.drainMonitorTouches(self.peripheralName, 12)
    if self.buffer then
        self.buffer.setVisible(true)
    end

    self.peripheral.clear()
    self:render()
    self:scheduleRender()
end

function Monitor:render()
    MonitorRenderer.render(self)
end

function Monitor:drawDependencyStatus(contextKey)
    MonitorRenderer.drawDependencyStatus(self, contextKey)
end

function Monitor:scheduleRender(offset)
    if not self.connected or self.inConfigMenu then
        return
    end

    if self.renderTimer then
        os.cancelTimer(self.renderTimer)
    end

    local sleepTime = (self.view and self.view.sleepTime) or 1
    local phase = offset
    if phase == nil then
        phase = self.renderPhase or 0
    end
    self.renderTimer = os.startTimer(sleepTime + phase)
end

function Monitor:handleTouch(monitorName, x, y)
    return MonitorTouch.handleTouch(self, monitorName, x, y)
end

function Monitor:handleTimer(timerId)
    if timerId == self.settingsTimer then
        self:hideSettingsButton()
        return true
    elseif timerId == self.loadRetryTimer then
        self.loadRetryTimer = nil
        if not self.connected then
            return true
        end
        if not self.viewInstance then
            local reloaded = self:loadView(self.viewName or "Clock")
            if not reloaded then
                self:scheduleLoadRetry(2)
            end
        end
        return true
    elseif timerId == self.renderTimer then
        local ok, err = pcall(function()
            self:render()
        end)
        if not ok then
            print("[Monitor] Render error on " .. (self.peripheralName or "unknown") .. ": " .. tostring(err))
        end
        self:scheduleRender()
        return true
    end
    return false
end

function Monitor:isRenderTimer(timerId)
    return timerId == self.renderTimer
        or timerId == self.settingsTimer
        or timerId == self.loadRetryTimer
end

function Monitor:clear()
    if self.connected then
        if self.buffer then
            Core.clear(self.buffer)
        end
        Core.clear(self.peripheral)
    end
end

function Monitor:disconnect()
    self.connected = false
    self.peripheral = nil
    self.buffer = nil
    self.view = nil
    self.viewInstance = nil
    self.showingSettings = false
    self.settingsButton = nil
    self.inConfigMenu = false

    if self.renderTimer then
        os.cancelTimer(self.renderTimer)
        self.renderTimer = nil
    end
    if self.loadRetryTimer then
        os.cancelTimer(self.loadRetryTimer)
        self.loadRetryTimer = nil
    end
    if self.settingsTimer then
        os.cancelTimer(self.settingsTimer)
        self.settingsTimer = nil
    end
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
    self.peripheral = peripheral.wrap(self.peripheralName)
    self.connected = self.peripheral ~= nil

    if self.connected then
        self:initialize()
    end

    return self.connected
end

function Monitor:adoptPeripheralName(newPeripheralName)
    if not newPeripheralName or newPeripheralName == "" then
        return false
    end

    local oldPeripheralName = self.peripheralName
    if self.connected then
        self:disconnect()
    end

    self.peripheralName = newPeripheralName
    if self.label == oldPeripheralName then
        self.label = newPeripheralName
    end

    return self:reconnect()
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
    if self.viewInstance and not self.pairingMode then
        self:render()
        self:scheduleRender()
    elseif self.connected and not self.inConfigMenu then
        self:scheduleLoadRetry(1)
    end

    while running.value do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "timer" then
            self:handleTimer(p1)
        elseif event == "monitor_touch" then
            self:handleTouch(p1, p2, p3)
        elseif event == "monitor_resize" then
            if p1 == self.peripheralName then
                self:handleResize()
            end
        elseif event == "peripheral" then
            if p1 == self.peripheralName and not self.connected then
                if self:reconnect() then
                    self:render()
                    self:scheduleRender()
                end
            end
        elseif event == "peripheral_detach" then
            if p1 == self.peripheralName and self.connected then
                self:disconnect()
            end
        end
    end
end

return Monitor
