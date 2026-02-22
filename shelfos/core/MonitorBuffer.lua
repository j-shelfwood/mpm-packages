local Theme = mpm('utils/Theme')

local MonitorBuffer = {}

local function calculateTextScale(monitor)
    monitor.setTextScale(1.0)
    local nativeWidth, nativeHeight = monitor.getSize()
    local _ = nativeWidth * nativeHeight

    local scale = 1.0
    monitor.setTextScale(scale)

    local width, height = monitor.getSize()
    return scale, width, height
end

function MonitorBuffer.initialize(monitor)
    if not monitor.connected then
        return
    end

    monitor.currentScale, monitor.bufferWidth, monitor.bufferHeight = calculateTextScale(monitor.peripheral)
    monitor.buffer = window.create(monitor.peripheral, 1, 1, monitor.bufferWidth, monitor.bufferHeight, true)

    Theme.apply(monitor.peripheral, monitor.themeName)
    Theme.apply(monitor.buffer, monitor.themeName)
end

function MonitorBuffer.handleResize(monitor)
    return MonitorBuffer.refresh(monitor)
end

function MonitorBuffer.refresh(monitor)
    if not monitor.connected then
        return
    end

    if monitor.handlingResize then
        return
    end
    monitor.handlingResize = true

    monitor.currentScale, monitor.bufferWidth, monitor.bufferHeight = calculateTextScale(monitor.peripheral)
    monitor.buffer = window.create(monitor.peripheral, 1, 1, monitor.bufferWidth, monitor.bufferHeight, true)

    Theme.apply(monitor.peripheral, monitor.themeName)
    Theme.apply(monitor.buffer, monitor.themeName)

    if monitor.viewName then
        monitor:loadView(monitor.viewName)
    end

    monitor.handlingResize = false
end

function MonitorBuffer.applyTheme(monitor)
    if not monitor.connected then
        return
    end

    Theme.apply(monitor.peripheral, monitor.themeName)
    if monitor.buffer then
        Theme.apply(monitor.buffer, monitor.themeName)
    end
end

return MonitorBuffer
