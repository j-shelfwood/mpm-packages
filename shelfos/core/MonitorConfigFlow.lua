local MonitorConfigMenu = mpm('shelfos/core/MonitorConfigMenu')
local EventLoop = mpm('ui/EventLoop')

local MonitorConfigFlow = {}

local TOUCH_DEBOUNCE_MS = 350
local CONFIG_EXIT_TOUCH_GUARD_MS = 700

function MonitorConfigFlow.openConfigMenu(monitor)
    if monitor.inConfigMenu then
        return
    end

    monitor.touchDebounceUntil = os.epoch("utc") + TOUCH_DEBOUNCE_MS
    EventLoop.armTouchGuard(monitor.peripheralName, TOUCH_DEBOUNCE_MS)
    EventLoop.drainMonitorTouches(monitor.peripheralName, 8)
    monitor.inConfigMenu = true
    monitor.showingSettings = false
    monitor.settingsButton = nil

    monitor:cancelTimers()

    if monitor.buffer then
        monitor.buffer.setVisible(false)
    end

    local ok, selectedView, newConfig = pcall(MonitorConfigMenu.openConfigFlow, monitor)
    local didLoadView = false

    if not ok then
        print("[Monitor] Config menu error on " .. (monitor.peripheralName or "unknown") .. ": " .. tostring(selectedView))
    elseif selectedView then
        local pendingConfig = newConfig or {}
        local previousConfig = monitor.viewConfig
        monitor.viewConfig = pendingConfig
        didLoadView = monitor:loadView(selectedView) and true or false
        if didLoadView and monitor.onViewChange then
            monitor.onViewChange(monitor.peripheralName, selectedView, monitor.viewConfig)
        elseif not didLoadView then
            monitor.viewConfig = previousConfig
        end
    end

    MonitorConfigFlow.closeConfigMenu(monitor)
end

function MonitorConfigFlow.closeConfigMenu(monitor)
    monitor.inConfigMenu = false
    monitor.touchDebounceUntil = os.epoch("utc") + CONFIG_EXIT_TOUCH_GUARD_MS
    EventLoop.armTouchGuard(monitor.peripheralName, CONFIG_EXIT_TOUCH_GUARD_MS)
    EventLoop.drainMonitorTouches(monitor.peripheralName, 12)

    if monitor.buffer then
        monitor.buffer.setVisible(true)
    end

    monitor.peripheral.clear()
    monitor:render()
    monitor:scheduleRender()
end

return MonitorConfigFlow
