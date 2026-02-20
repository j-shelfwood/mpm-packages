local RenderContext = mpm('net/RenderContext')
local DependencyStatus = mpm('net/DependencyStatus')

local MonitorRenderer = {}

function MonitorRenderer.drawDependencyStatus(monitor, contextKey)
    if not monitor.buffer or not contextKey then
        return
    end

    local deps = DependencyStatus.getContext(contextKey)
    if not deps or #deps == 0 then
        return
    end

    local y = monitor.bufferHeight
    local maxDots = math.max(1, monitor.bufferWidth - 1)
    local count = math.min(#deps, maxDots)

    monitor.buffer.setBackgroundColor(colors.black)
    for i = 1, count do
        local dep = deps[i]
        local color = colors.lime
        if dep.state == "pending" then
            color = colors.orange
        elseif dep.state == "error" then
            color = colors.red
        end

        monitor.buffer.setCursorPos(i, y)
        monitor.buffer.setTextColor(color)
        monitor.buffer.write(".")
    end

    if #deps > count then
        monitor.buffer.setCursorPos(math.min(monitor.bufferWidth, count + 1), y)
        monitor.buffer.setTextColor(colors.lightGray)
        monitor.buffer.write("+")
    end

    monitor.buffer.setTextColor(colors.white)
end

function MonitorRenderer.render(monitor)
    if not monitor.connected or not monitor.buffer or monitor.inConfigMenu or not monitor.viewInstance then
        return
    end

    local data, dataErr
    local getDataOk = true
    local contextKey = (monitor.peripheralName or "unknown") .. "|" .. (monitor.viewName or "unknown")

    if monitor.view.getData then
        RenderContext.set(contextKey)
        getDataOk, dataErr = pcall(function()
            data = monitor.view.getData(monitor.viewInstance)
        end)
        RenderContext.clear()
    end

    monitor.buffer.setVisible(false)
    monitor.buffer.setBackgroundColor(colors.black)
    monitor.buffer.clear()

    if not getDataOk then
        print("[Monitor] getData error in " .. (monitor.viewName or "unknown") .. ": " .. tostring(dataErr))

        if monitor.view.renderError then
            pcall(monitor.view.renderError, monitor.viewInstance, tostring(dataErr))
        else
            monitor.buffer.setCursorPos(1, 1)
            monitor.buffer.setTextColor(colors.red)
            monitor.buffer.write("Data Error")

            if monitor.bufferHeight >= 3 and dataErr then
                monitor.buffer.setCursorPos(1, 3)
                monitor.buffer.setTextColor(colors.gray)
                local errStr = tostring(dataErr):sub(1, monitor.bufferWidth)
                monitor.buffer.write(errStr)
            end
            monitor.buffer.setTextColor(colors.white)
        end
    else
        local renderOk, renderErr

        if monitor.view.renderWithData then
            renderOk, renderErr = pcall(monitor.view.renderWithData, monitor.viewInstance, data)
        else
            renderOk, renderErr = pcall(monitor.view.render, monitor.viewInstance)
        end

        if not renderOk then
            print("[Monitor] Render error in " .. (monitor.viewName or "unknown") .. ": " .. tostring(renderErr))

            monitor.buffer.setCursorPos(1, 1)
            monitor.buffer.setTextColor(colors.red)
            monitor.buffer.write("Render Error")

            if monitor.bufferHeight >= 3 and renderErr then
                monitor.buffer.setCursorPos(1, 3)
                monitor.buffer.setTextColor(colors.gray)
                local errStr = tostring(renderErr):sub(1, monitor.bufferWidth)
                monitor.buffer.write(errStr)
            end
            monitor.buffer.setTextColor(colors.white)
        end
    end

    if monitor.showingSettings and monitor.settingsButton then
        monitor.settingsButton:render()
    end

    MonitorRenderer.drawDependencyStatus(monitor, contextKey)
    monitor.buffer.setVisible(true)
end

return MonitorRenderer
