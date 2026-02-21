local Core = mpm('ui/Core')

local MonitorLifecycle = {}

local function getListenEvents(monitor)
    if monitor and monitor.viewInstance and type(monitor.viewInstance.listenEvents) == "table" then
        return monitor.viewInstance.listenEvents
    end
    if monitor and monitor.view and type(monitor.view.listenEvents) == "table" then
        return monitor.view.listenEvents
    end
    return {}
end

local function listensFor(monitor, eventName)
    local events = getListenEvents(monitor)
    for _, name in ipairs(events) do
        if name == eventName then
            return true
        end
    end
    return false
end

local function dispatchViewEvent(monitor, eventName, p1, p2, p3)
    if not monitor or not monitor.viewInstance or monitor.inConfigMenu or monitor.pairingMode then
        return false
    end
    if not listensFor(monitor, eventName) then
        return false
    end
    if type(monitor.viewInstance.onEvent) ~= "function" then
        return false
    end
    local ok, shouldRender = pcall(monitor.viewInstance.onEvent, monitor.viewInstance, eventName, p1, p2, p3)
    if not ok then
        print("[Monitor] Event error on " .. (monitor.peripheralName or "unknown") .. ": " .. tostring(shouldRender))
        return false
    end
    if shouldRender then
        monitor:render()
    end
    return true
end

function MonitorLifecycle.scheduleLoadRetry(monitor, delaySeconds)
    if monitor.inConfigMenu then
        return
    end

    if monitor.loadRetryTimer then
        os.cancelTimer(monitor.loadRetryTimer)
    end

    monitor.loadRetryTimer = os.startTimer(delaySeconds or 2)
end

function MonitorLifecycle.scheduleRender(monitor, offset)
    if not monitor.connected or monitor.inConfigMenu then
        return
    end

    if not listensFor(monitor, "timer") then
        return
    end

    if monitor.renderTimer then
        os.cancelTimer(monitor.renderTimer)
    end

    local sleepTime = (monitor.view and monitor.view.sleepTime) or 1
    local phase = offset
    if phase == nil then
        phase = monitor.renderPhase or 0
    end
    monitor.renderTimer = os.startTimer(sleepTime + phase)
end

function MonitorLifecycle.cancelTimers(monitor)
    if monitor.renderTimer then
        os.cancelTimer(monitor.renderTimer)
        monitor.renderTimer = nil
    end
    if monitor.loadRetryTimer then
        os.cancelTimer(monitor.loadRetryTimer)
        monitor.loadRetryTimer = nil
    end
    if monitor.settingsTimer then
        os.cancelTimer(monitor.settingsTimer)
        monitor.settingsTimer = nil
    end
end

function MonitorLifecycle.handleTimer(monitor, timerId)
    if timerId == monitor.settingsTimer then
        monitor:hideSettingsButton()
        return true
    elseif timerId == monitor.loadRetryTimer then
        monitor.loadRetryTimer = nil
        if not monitor.connected then
            return true
        end
        if not monitor.viewInstance then
            local reloaded = monitor:loadView(monitor.viewName or "Clock")
            if not reloaded then
                monitor:scheduleLoadRetry(2)
            end
        end
        return true
    elseif timerId == monitor.renderTimer then
        local ok, err = pcall(function()
            if not dispatchViewEvent(monitor, "timer", timerId) then
                monitor:render()
            end
        end)
        if not ok then
            print("[Monitor] Render error on " .. (monitor.peripheralName or "unknown") .. ": " .. tostring(err))
        end
        monitor:scheduleRender()
        return true
    end
    return false
end

function MonitorLifecycle.clear(monitor)
    if monitor.connected then
        if monitor.buffer then
            Core.clear(monitor.buffer)
        end
        Core.clear(monitor.peripheral)
    end
end

function MonitorLifecycle.disconnect(monitor)
    monitor.connected = false
    monitor.peripheral = nil
    monitor.buffer = nil
    monitor.view = nil
    monitor.viewInstance = nil
    monitor.showingSettings = false
    monitor.settingsButton = nil
    monitor.inConfigMenu = false

    MonitorLifecycle.cancelTimers(monitor)
end

function MonitorLifecycle.reconnect(monitor)
    monitor.peripheral = peripheral.wrap(monitor.peripheralName)
    monitor.connected = monitor.peripheral ~= nil

    if monitor.connected then
        monitor:initialize()
    end

    return monitor.connected
end

function MonitorLifecycle.adoptPeripheralName(monitor, newPeripheralName)
    if not newPeripheralName or newPeripheralName == "" then
        return false
    end

    local oldPeripheralName = monitor.peripheralName
    if monitor.connected then
        monitor:disconnect()
    end

    monitor.peripheralName = newPeripheralName
    if monitor.label == oldPeripheralName then
        monitor.label = newPeripheralName
    end

    return monitor:reconnect()
end

function MonitorLifecycle.runLoop(monitor, running)
    local function isRunning()
        if type(running) == "table" then
            if running.value == nil then
                return true
            end
            return running.value == true
        end
        if type(running) == "boolean" then
            return running
        end
        -- Backward compatibility for legacy call sites that omitted runningRef.
        return true
    end

    if monitor.viewInstance and not monitor.pairingMode then
        monitor:render()
        monitor:scheduleRender()
    elseif monitor.connected and not monitor.inConfigMenu then
        monitor:scheduleLoadRetry(1)
    end

    while isRunning() do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "timer" then
            monitor:handleTimer(p1)
        elseif event == "monitor_touch" then
            monitor:handleTouch(p1, p2, p3)
        elseif event == "monitor_resize" then
            if p1 == monitor.peripheralName then
                monitor:handleResize()
            end
        elseif event == "peripheral" then
            if p1 == monitor.peripheralName and not monitor.connected then
                if monitor:reconnect() then
                    monitor:render()
                    monitor:scheduleRender()
                end
            end
        elseif event == "peripheral_detach" then
            if p1 == monitor.peripheralName and monitor.connected then
                monitor:disconnect()
            end
        else
            dispatchViewEvent(monitor, event, p1, p2, p3)
        end
    end
end

return MonitorLifecycle
