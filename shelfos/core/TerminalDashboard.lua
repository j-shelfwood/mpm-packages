-- TerminalDashboard.lua
-- Live terminal dashboard for ShelfOS display mode (Kernel runtime)

local Terminal = mpm('shelfos/core/Terminal')
local TermUI = mpm('ui/TermUI')
local DashboardUtils = mpm('shelfos/core/DashboardUtils')

local TerminalDashboard = {}
TerminalDashboard.__index = TerminalDashboard

function TerminalDashboard.new()
    local self = setmetatable({}, TerminalDashboard)
    self.startedAt = os.epoch("utc")
    self.identityName = "Unknown"
    self.identityId = "N/A"
    self.networkLabel = "Booting"
    self.networkColor = colors.lightGray
    self.networkState = "booting" -- booting|connected|offline
    self.modemType = "n/a"
    self.lastActivity = {}
    self.stats = {
        announce = 0,
        discover = 0,
        call = 0,
        call_error = 0,
        rescan = 0,
        rx = 0
    }
    self.rate = { msgPerSec = 0 }
    self.prevRxCount = 0
    self.lastRateSampleAt = os.epoch("utc")
    self.waitMsSamples = {}
    self.handlerMsSamples = {}
    self.callDurationSamples = {}
    self.message = "Booting..."
    self.messageColor = colors.lightGray
    self.messageAt = os.epoch("utc")
    self.redrawPending = true
    self.lastRenderAt = 0
    return self
end

function TerminalDashboard:requestRedraw()
    self.redrawPending = true
end

function TerminalDashboard:setIdentity(name, id)
    self.identityName = name or self.identityName
    self.identityId = id or self.identityId
    self.redrawPending = true
end

function TerminalDashboard:setNetwork(label, color, modemType, state)
    self.networkLabel = label or self.networkLabel
    self.networkColor = color or self.networkColor
    self.networkState = state or ((label == "Connected") and "connected" or "offline")
    if modemType then self.modemType = modemType end
    self.redrawPending = true
end

function TerminalDashboard:setMessage(message, color)
    self.message = message or self.message
    self.messageColor = color or colors.lightGray
    self.messageAt = os.epoch("utc")
    self.redrawPending = true
end

function TerminalDashboard:markActivity(key, message, color)
    self.lastActivity[key] = os.epoch("utc")
    if self.stats[key] ~= nil then
        self.stats[key] = self.stats[key] + 1
    end
    self:setMessage(message, color)
end

function TerminalDashboard:recordNetworkDrain(drained)
    if (drained or 0) > 0 then
        self.stats.rx = self.stats.rx + drained
        self.lastActivity.rx = os.epoch("utc")
        self.redrawPending = true
    end
end

function TerminalDashboard:recordEventWaitMs(ms)
    DashboardUtils.appendSample(self.waitMsSamples, ms or 0, 100)
end

function TerminalDashboard:recordHandlerMs(ms)
    DashboardUtils.appendSample(self.handlerMsSamples, ms or 0, 100)
end

function TerminalDashboard:recordCallMs(ms)
    DashboardUtils.appendSample(self.callDurationSamples, ms or 0, 80)
end

function TerminalDashboard:onHostActivity(activity, data)
    data = data or {}
    if activity == "discover" then
        self:markActivity("discover", "Discovery request from #" .. tostring(data.senderId or "?"), colors.yellow)
    elseif activity == "call" then
        self:markActivity("call", tostring(data.method or "call") .. " on " .. tostring(data.peripheral or "unknown"), colors.lime)
        self:recordCallMs(data.durationMs)
    elseif activity == "call_error" then
        self:markActivity("call_error", "Call error: " .. tostring(data.error or "unknown"), colors.red)
        self:recordCallMs(data.durationMs)
    elseif activity == "announce" then
        self:markActivity("announce", "Announced " .. tostring(data.peripheralCount or 0) .. " peripheral(s)", colors.cyan)
    elseif activity == "rescan" then
        self:markActivity("rescan", "Rescan " .. tostring(data.oldCount or 0) .. " -> " .. tostring(data.newCount or 0), colors.orange)
    elseif activity == "start" then
        self:setMessage("Sharing " .. tostring(data.peripheralCount or 0) .. " local peripheral(s)", colors.lightGray)
    end
end

function TerminalDashboard:tick()
    local now = os.epoch("utc")
    local elapsed = now - self.lastRateSampleAt
    if elapsed >= 1000 then
        local rxDelta = self.stats.rx - self.prevRxCount
        self.rate.msgPerSec = (rxDelta * 1000) / elapsed
        self.prevRxCount = self.stats.rx
        self.lastRateSampleAt = now
    end
end

-- Determine whether dashboard should render on this frame.
-- Keeps live metrics/uptime fresh while avoiding unnecessary redraw churn.
function TerminalDashboard:shouldRender(nowMs)
    local now = nowMs or os.epoch("utc")
    if self.redrawPending then
        return true
    end
    return (now - self.lastRenderAt) >= 1000
end

local function drawMetricBounded(x, y, width, label, value, valueColor)
    if width <= 0 then
        return
    end

    local labelText = tostring(label or "") .. ": "
    local valueText = tostring(value or "")
    local safeWidth = math.max(1, width)

    term.setCursorPos(x, y)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)

    if #labelText >= safeWidth then
        term.write(DashboardUtils.truncateText(labelText, safeWidth))
        term.setTextColor(colors.white)
        return
    end

    term.write(labelText)
    term.setTextColor(valueColor or colors.white)
    term.write(DashboardUtils.truncateText(valueText, safeWidth - #labelText))
    term.setTextColor(colors.white)
end

local function drawActivityBounded(x, y, width, label, lastActivityTs, count, opts)
    if width <= 0 then
        return
    end

    opts = opts or {}
    local flashMs = opts.flashMs or 700
    local activeColor = opts.activeColor or colors.lime
    local idleColor = opts.idleColor or colors.gray
    local labelColor = opts.labelColor or colors.lightGray
    local countColor = opts.countColor or colors.white
    local now = os.epoch("utc")
    local isActive = lastActivityTs and ((now - lastActivityTs) <= flashMs) or false
    local safeWidth = math.max(1, width)

    term.setCursorPos(x, y)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write("[")
    if safeWidth <= 1 then
        return
    end

    term.setBackgroundColor(isActive and activeColor or idleColor)
    term.write(" ")
    if safeWidth <= 2 then
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        return
    end

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write("] ")
    if safeWidth <= 4 then
        return
    end

    local remaining = safeWidth - 4
    local labelText = tostring(label or "")
    if count == nil then
        term.setTextColor(labelColor)
        term.write(DashboardUtils.truncateText(labelText, remaining))
        term.setTextColor(colors.white)
        return
    end

    local countText = " " .. tostring(count)
    if #countText >= remaining then
        term.setTextColor(labelColor)
        term.write(DashboardUtils.truncateText(labelText .. countText, remaining))
        term.setTextColor(colors.white)
        return
    end

    local labelWidth = remaining - #countText
    term.setTextColor(labelColor)
    term.write(DashboardUtils.truncateText(labelText, labelWidth))
    term.setTextColor(countColor)
    term.write(countText)
    term.setTextColor(colors.white)
end

function TerminalDashboard:render(kernel)
    if Terminal.isDialogOpen() then
        return
    end

    local logWin = Terminal.getLogWindow()
    local old = term.redirect(logWin)

    TermUI.refreshSize()
    TermUI.clear()
    TermUI.drawTitleBar("ShelfOS Dashboard")

    local w, h = TermUI.getSize()
    local contentX = 2
    local contentWidth = math.max(1, w - 1)
    local metricCols = DashboardUtils.layoutColumns(contentX, contentWidth, 2, 18, 3)
    local leftCol = metricCols[1]
    local rightCol = metricCols[2]
    local now = os.epoch("utc")
    local swarmOnline = self.networkState == "connected"

    local function drawMetricRow(y, leftLabel, leftValue, leftColor, rightLabel, rightValue, rightColor)
        drawMetricBounded(leftCol.x, y, leftCol.width, leftLabel, leftValue, leftColor)
        if rightCol and rightLabel then
            drawMetricBounded(rightCol.x, y, rightCol.width, rightLabel, rightValue, rightColor)
            return y + 1
        end

        local nextY = y + 1
        if rightLabel then
            drawMetricBounded(leftCol.x, nextY, leftCol.width, rightLabel, rightValue, rightColor)
            nextY = nextY + 1
        end
        return nextY
    end

    local y = 3
    y = drawMetricRow(y, "Computer", self.identityName, colors.white, "Uptime", DashboardUtils.formatUptime(now - self.startedAt), colors.white)
    y = drawMetricRow(y, "Computer ID", self.identityId, colors.lightGray, "Modem", self.modemType, colors.lightGray)
    if swarmOnline then
        y = drawMetricRow(y, "Network", self.networkLabel, self.networkColor, "Messages/s", string.format("%.1f", self.rate.msgPerSec), colors.cyan)
    else
        y = drawMetricRow(y, "Network", self.networkLabel, self.networkColor, nil, nil, nil)
    end

    if not swarmOnline then
        TermUI.drawText(contentX, y, DashboardUtils.truncateText("Swarm inactive (press L to pair)", contentWidth), colors.orange)
        y = y + 1
    end

    local monitorCount = kernel and #kernel.monitors or 0
    local sharedCount = 0
    local remoteCount = 0
    if kernel and kernel.peripheralHost then
        sharedCount = kernel.peripheralHost:getPeripheralCount()
    end
    if kernel and kernel.peripheralClient then
        remoteCount = kernel.peripheralClient:getCount()
    end
    if swarmOnline then
        y = drawMetricRow(y, "Monitors", monitorCount, colors.white, "Remote", remoteCount, colors.white)
    else
        y = drawMetricRow(y, "Monitors", monitorCount, colors.white, nil, nil, nil)
    end
    y = y + 2

    if swarmOnline then
        TermUI.drawSeparator(y, colors.gray)
        y = y + 1

        local activityCols = DashboardUtils.layoutColumns(contentX, contentWidth, 3, 14, 2)
        local activityItems = {
            { label = "DISCOVER", ts = self.lastActivity.discover, count = self.stats.discover },
            { label = "CALL", ts = self.lastActivity.call, count = self.stats.call },
            { label = "ANNOUNCE", ts = self.lastActivity.announce, count = self.stats.announce },
            { label = "RX", ts = self.lastActivity.rx, count = self.stats.rx },
            { label = "RESCAN", ts = self.lastActivity.rescan, count = self.stats.rescan },
            { label = "ERROR", ts = self.lastActivity.call_error, count = self.stats.call_error }
        }

        local perRow = #activityCols
        for idx, item in ipairs(activityItems) do
            local colIdx = ((idx - 1) % perRow) + 1
            local rowIdx = math.floor((idx - 1) / perRow)
            local box = activityCols[colIdx]
            drawActivityBounded(box.x, y + rowIdx, box.width, item.label, item.ts, item.count)
        end

        y = y + math.ceil(#activityItems / perRow) + 1
    else
        TermUI.drawSeparator(y, colors.gray)
        y = y + 1
        TermUI.drawText(contentX, y, DashboardUtils.truncateText("Swarm metrics hidden while offline", contentWidth), colors.lightGray)
        y = y + 2
    end

    local avgWaitMs = DashboardUtils.average(self.waitMsSamples)
    local peakWaitMs = DashboardUtils.maxValue(self.waitMsSamples)
    local avgHandlerMs = DashboardUtils.average(self.handlerMsSamples)
    local peakHandlerMs = DashboardUtils.maxValue(self.handlerMsSamples)
    local avgCallMs = DashboardUtils.average(self.callDurationSamples)
    local loopColor = colors.lime
    if avgHandlerMs > 120 then
        loopColor = colors.red
    elseif avgHandlerMs > 60 then
        loopColor = colors.orange
    end
    if swarmOnline then
        y = drawMetricRow(y, "Wait avg/peak", string.format("%.0f/%.0f ms", avgWaitMs, peakWaitMs), colors.lightGray, "Call avg", string.format("%.0f ms", avgCallMs), colors.white)
    else
        y = drawMetricRow(y, "Wait avg/peak", string.format("%.0f/%.0f ms", avgWaitMs, peakWaitMs), colors.lightGray, nil, nil, nil)
    end
    y = drawMetricRow(y, "Handler avg/peak", string.format("%.0f/%.0f ms", avgHandlerMs, peakHandlerMs), loopColor, nil, nil, nil)
    if swarmOnline then
        y = drawMetricRow(y, "Shared Local", sharedCount, colors.white, nil, nil, nil)
    end
    y = y + 1

    if kernel and #kernel.monitors > 0 and y < h - 3 then
        TermUI.drawText(contentX, y, "Views", colors.lightGray)
        y = y + 1
        for _, monitor in ipairs(kernel.monitors) do
            if y >= h - 2 then break end
            local row = monitor:getName() .. " -> " .. (monitor:getViewName() or "None")
            TermUI.drawText(contentX + 1, y, DashboardUtils.truncateText(row, math.max(1, w - (contentX + 1))), colors.white)
            y = y + 1
        end
    end

    local statusColor = self.messageColor
    if now - self.messageAt > 5000 then
        statusColor = colors.gray
    end
    TermUI.clearLine(h)
    TermUI.drawText(2, h, DashboardUtils.truncateText(self.message, math.max(1, w - 2)), statusColor)

    term.redirect(old)
    self.redrawPending = false
    self.lastRenderAt = now
end

return TerminalDashboard
