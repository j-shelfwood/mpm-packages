-- TerminalDashboard.lua
-- Live terminal dashboard for ShelfOS display mode (Kernel runtime)

local Terminal = mpm('shelfos/core/Terminal')
local TermUI = mpm('ui/TermUI')

local TerminalDashboard = {}
TerminalDashboard.__index = TerminalDashboard

local function appendSample(samples, value, maxSamples)
    table.insert(samples, value)
    if #samples > maxSamples then
        table.remove(samples, 1)
    end
end

local function average(samples)
    if #samples == 0 then return 0 end
    local total = 0
    for _, value in ipairs(samples) do
        total = total + value
    end
    return total / #samples
end

local function maxValue(samples)
    local max = 0
    for _, value in ipairs(samples) do
        if value > max then max = value end
    end
    return max
end

local function truncateText(text, maxLen)
    text = tostring(text or "")
    if #text <= maxLen then return text end
    if maxLen <= 3 then return text:sub(1, maxLen) end
    return text:sub(1, maxLen - 3) .. "..."
end

local function formatUptime(ms)
    local seconds = math.floor((ms or 0) / 1000)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60

    if hours > 0 then
        return string.format("%dh %02dm %02ds", hours, minutes, secs)
    end
    if minutes > 0 then
        return string.format("%dm %02ds", minutes, secs)
    end
    return string.format("%ds", secs)
end

function TerminalDashboard.new()
    local self = setmetatable({}, TerminalDashboard)
    self.startedAt = os.epoch("utc")
    self.identityName = "Unknown"
    self.identityId = "N/A"
    self.networkLabel = "Booting"
    self.networkColor = colors.lightGray
    self.networkState = "booting" -- booting|connected|offline
    self.modemType = "n/a"
    self.sharedCount = 0
    self.remoteCount = 0
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
    self.loopMsSamples = {}
    self.callDurationSamples = {}
    self.message = "Booting..."
    self.messageColor = colors.lightGray
    self.messageAt = os.epoch("utc")
    self.needsRedraw = true
    return self
end

function TerminalDashboard:requestRedraw()
    self.needsRedraw = true
end

function TerminalDashboard:setIdentity(name, id)
    self.identityName = name or self.identityName
    self.identityId = id or self.identityId
    self.needsRedraw = true
end

function TerminalDashboard:setNetwork(label, color, modemType, state)
    self.networkLabel = label or self.networkLabel
    self.networkColor = color or self.networkColor
    self.networkState = state or ((label == "Connected") and "connected" or "offline")
    if modemType then self.modemType = modemType end
    self.needsRedraw = true
end

function TerminalDashboard:setSharedCount(count)
    self.sharedCount = count or 0
    self.needsRedraw = true
end

function TerminalDashboard:setRemoteCount(count)
    self.remoteCount = count or 0
    self.needsRedraw = true
end

function TerminalDashboard:setMessage(message, color)
    self.message = message or self.message
    self.messageColor = color or colors.lightGray
    self.messageAt = os.epoch("utc")
    self.needsRedraw = true
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
        self.needsRedraw = true
    end
end

function TerminalDashboard:recordLoopMs(ms)
    appendSample(self.loopMsSamples, ms or 0, 100)
end

function TerminalDashboard:recordCallMs(ms)
    appendSample(self.callDurationSamples, ms or 0, 80)
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
        self:setSharedCount(data.newCount or self.sharedCount)
    elseif activity == "start" then
        self:setSharedCount(data.peripheralCount or self.sharedCount)
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

function TerminalDashboard:render(kernel)
    local logWin = Terminal.getLogWindow()
    local old = term.redirect(logWin)

    TermUI.refreshSize()
    TermUI.clear()
    TermUI.drawTitleBar("ShelfOS Dashboard")

    local w, h = TermUI.getSize()
    local rightCol = math.max(2, math.floor(w / 2))
    local now = os.epoch("utc")

    local y = 3
    local swarmOnline = self.networkState == "connected"
    TermUI.drawMetric(2, y, "Computer", self.identityName, colors.white)
    TermUI.drawMetric(rightCol, y, "Uptime", formatUptime(now - self.startedAt), colors.white)
    y = y + 1
    TermUI.drawMetric(2, y, "Computer ID", self.identityId, colors.lightGray)
    TermUI.drawMetric(rightCol, y, "Modem", self.modemType, colors.lightGray)
    y = y + 1
    TermUI.drawMetric(2, y, "Network", self.networkLabel, self.networkColor)
    TermUI.drawMetric(rightCol, y, "Messages/s", swarmOnline and string.format("%.1f", self.rate.msgPerSec) or "n/a", swarmOnline and colors.cyan or colors.gray)
    y = y + 1
    if not swarmOnline then
        TermUI.drawText(2, y, "Swarm inactive (press L to pair)", colors.orange)
        y = y + 1
    end

    local monitorCount = kernel and #kernel.monitors or 0
    TermUI.drawMetric(2, y, "Monitors", monitorCount, colors.white)
    TermUI.drawMetric(rightCol, y, "Remote", swarmOnline and self.remoteCount or "n/a", swarmOnline and colors.white or colors.gray)
    y = y + 2

    TermUI.drawSeparator(y, colors.gray)
    y = y + 1
    local col2 = math.max(2, math.floor(w / 3) + 1)
    local col3 = math.max(col2 + 1, math.floor((w * 2) / 3) + 1)
    local activityOpts = swarmOnline and {} or { idleColor = colors.lightGray, labelColor = colors.gray, countColor = colors.gray }
    TermUI.drawActivityLight(2, y, "DISCOVER", self.lastActivity.discover, swarmOnline and self.stats.discover or "n/a", activityOpts)
    TermUI.drawActivityLight(col2, y, "CALL", self.lastActivity.call, swarmOnline and self.stats.call or "n/a", activityOpts)
    TermUI.drawActivityLight(col3, y, "ANNOUNCE", self.lastActivity.announce, swarmOnline and self.stats.announce or "n/a", activityOpts)
    y = y + 1
    TermUI.drawActivityLight(2, y, "RX", self.lastActivity.rx, swarmOnline and self.stats.rx or "n/a", activityOpts)
    TermUI.drawActivityLight(col2, y, "RESCAN", self.lastActivity.rescan, swarmOnline and self.stats.rescan or "n/a", activityOpts)
    TermUI.drawActivityLight(col3, y, "ERROR", self.lastActivity.call_error, swarmOnline and self.stats.call_error or "n/a", activityOpts)
    y = y + 2

    local avgLoopMs = average(self.loopMsSamples)
    local peakLoopMs = maxValue(self.loopMsSamples)
    local avgCallMs = average(self.callDurationSamples)
    local loopColor = colors.lime
    if avgLoopMs > 120 then
        loopColor = colors.red
    elseif avgLoopMs > 60 then
        loopColor = colors.orange
    end
    TermUI.drawMetric(2, y, "Loop avg/peak", string.format("%.0f/%.0f ms", avgLoopMs, peakLoopMs), loopColor)
    TermUI.drawMetric(rightCol, y, "Call avg", swarmOnline and string.format("%.0f ms", avgCallMs) or "n/a", swarmOnline and colors.white or colors.gray)
    y = y + 1
    TermUI.drawMetric(2, y, "Shared Local", swarmOnline and self.sharedCount or "n/a", swarmOnline and colors.white or colors.gray)
    y = y + 2

    if kernel and #kernel.monitors > 0 and y < h - 3 then
        TermUI.drawText(2, y, "Views", colors.lightGray)
        y = y + 1
        for _, monitor in ipairs(kernel.monitors) do
            if y >= h - 2 then break end
            local row = monitor:getName() .. " -> " .. (monitor:getViewName() or "None")
            TermUI.drawText(3, y, truncateText(row, math.max(1, w - 3)), colors.white)
            y = y + 1
        end
    end

    local statusColor = self.messageColor
    if now - self.messageAt > 5000 then
        statusColor = colors.gray
    end
    TermUI.clearLine(h)
    TermUI.drawText(2, h, truncateText(self.message, math.max(1, w - 2)), statusColor)

    term.redirect(old)
end

return TerminalDashboard
