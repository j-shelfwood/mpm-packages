local Button = mpm('ui/Button')

local MonitorTouch = {}

function MonitorTouch.drawSettingsButton(monitor)
    local buttonLabel = "[*]"
    local buttonX = monitor.bufferWidth - #buttonLabel - 2
    local buttonY = monitor.bufferHeight - 1

    buttonX = math.max(1, buttonX)
    buttonY = math.max(1, buttonY)

    monitor.settingsButton = Button.neutral(monitor.buffer, buttonX, buttonY, buttonLabel, nil, {
        padding = 1
    })
    monitor.settingsButton:render()

    monitor.showingSettings = true

    if monitor.settingsTimer then
        os.cancelTimer(monitor.settingsTimer)
    end
    monitor.settingsTimer = os.startTimer(3)
end

function MonitorTouch.hideSettingsButton(monitor)
    monitor.showingSettings = false
    monitor.settingsTimer = nil
    monitor.settingsButton = nil
end

function MonitorTouch.isSettingsButtonTouch(monitor, x, y)
    if not monitor.settingsButton then
        return false
    end
    return monitor.settingsButton:contains(x, y)
end

function MonitorTouch.handleTouch(monitor, monitorName, x, y)
    if monitorName ~= monitor.peripheralName then
        return false
    end

    if monitor.pairingMode then
        return false
    end

    if monitor.inConfigMenu then
        return false
    end

    local now = os.epoch("utc")
    if now < (monitor.touchDebounceUntil or 0) then
        return true
    end

    if y == 1 then
        monitor:openConfigMenu()
        return true
    end

    if monitor.showingSettings and MonitorTouch.isSettingsButtonTouch(monitor, x, y) then
        monitor:openConfigMenu()
        return true
    end

    MonitorTouch.drawSettingsButton(monitor)

    if monitor.view and monitor.view.handleTouch and monitor.viewInstance then
        local ok, handled = pcall(monitor.view.handleTouch, monitor.viewInstance, x, y)
        if not ok then
            print("[Monitor] Touch handler error on " .. (monitor.peripheralName or "unknown") .. ": " .. tostring(handled))
            handled = false
        end
        if handled then
            monitor:render()
        end
    end

    return true
end

return MonitorTouch
