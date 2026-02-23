local TermUI = mpm('ui/TermUI')

local Dashboard = {}
Dashboard.__index = Dashboard

local function nowMs()
    return os.epoch("utc")
end

local function formatSeconds(ms)
    if not ms or ms <= 0 then
        return "-"
    end
    return string.format("%.1fs", ms / 1000)
end

local function formatAge(ts)
    if not ts or ts <= 0 then
        return "-"
    end
    return formatSeconds(nowMs() - ts)
end

local function formatIn(ts)
    if not ts or ts <= 0 then
        return "-"
    end
    local diff = ts - nowMs()
    if diff < 0 then diff = 0 end
    return formatSeconds(diff)
end

local function truncate(text, maxLen)
    if not text then
        return ""
    end
    if #text <= maxLen then
        return text
    end
    if maxLen <= 3 then
        return text:sub(1, maxLen)
    end
    return text:sub(1, maxLen - 3) .. "..."
end

function Dashboard.new(config, influx, poller)
    local self = setmetatable({}, Dashboard)
    self.config = config
    self.influx = influx
    self.poller = poller
    self.startedAt = nowMs()
    self.lastEvent = "startup"
    self.lastEventAt = self.startedAt
    self.dirty = true
    return self
end

function Dashboard:markDirty()
    self.dirty = true
    pcall(os.queueEvent, "collector_dirty")
end

function Dashboard:recordEvent(kind)
    if kind then
        self.lastEvent = kind
        self.lastEventAt = nowMs()
    end
    self:markDirty()
end

function Dashboard:render()
    TermUI.clear()
    TermUI.drawTitleBar("Influx Collector")

    local w, h = TermUI.getSize()
    local y = 2

    local endpoint = truncate(self.config.url or "-", math.max(8, w - 12))
    TermUI.drawInfoLine(y, "Node", self.config.node or "-", colors.white); y = y + 1
    TermUI.drawInfoLine(y, "Endpoint", endpoint, colors.white); y = y + 1

    TermUI.drawSeparator(y); y = y + 1

    local influxStatus = self.influx:getStatus()
    local pollerStats = self.poller.stats or {}
    local schedule = self.poller:getSchedule()

    TermUI.drawInfoLine(y, "Buffer", tostring(influxStatus.bufferLines or 0) .. " lines", colors.white); y = y + 1
    TermUI.drawInfoLine(y, "Last flush", string.format("%s | %s | %s lines",
        influxStatus.lastFlushStatus or "-",
        formatAge(influxStatus.lastFlushAt),
        tostring(influxStatus.lastBatchLines or 0)
    ), influxStatus.lastFlushStatus == "error" and colors.red or colors.lime); y = y + 1

    if influxStatus.lastError and influxStatus.lastError ~= "" then
        TermUI.drawInfoLine(y, "Error", truncate(influxStatus.lastError, w - 10), colors.red); y = y + 1
    end

    TermUI.drawSeparator(y); y = y + 1

    TermUI.drawInfoLine(y, "Machines", string.format("%d | %s | %s",
        (pollerStats.machines and pollerStats.machines.count) or 0,
        formatAge(pollerStats.machines and pollerStats.machines.last_at),
        formatSeconds(pollerStats.machines and pollerStats.machines.duration_ms)
    ), colors.white); y = y + 1

    TermUI.drawInfoLine(y, "Energy", string.format("%d | %s | %s",
        (pollerStats.energy and pollerStats.energy.count) or 0,
        formatAge(pollerStats.energy and pollerStats.energy.last_at),
        formatSeconds(pollerStats.energy and pollerStats.energy.duration_ms)
    ), colors.white); y = y + 1

    TermUI.drawInfoLine(y, "Detectors", string.format("%d | %s | %s",
        (pollerStats.detectors and pollerStats.detectors.count) or 0,
        formatAge(pollerStats.detectors and pollerStats.detectors.last_at),
        formatSeconds(pollerStats.detectors and pollerStats.detectors.duration_ms)
    ), colors.white); y = y + 1

    TermUI.drawInfoLine(y, "AE", string.format("%d items | %d fluids | %s",
        (pollerStats.ae and pollerStats.ae.items) or 0,
        (pollerStats.ae and pollerStats.ae.fluids) or 0,
        formatAge(pollerStats.ae and pollerStats.ae.last_at)
    ), colors.white); y = y + 1

    TermUI.drawSeparator(y); y = y + 1

    TermUI.drawInfoLine(y, "Next machine", formatIn(schedule.nextMachineAt), colors.lightGray); y = y + 1
    TermUI.drawInfoLine(y, "Next energy", formatIn(schedule.nextEnergyAt), colors.lightGray); y = y + 1
    TermUI.drawInfoLine(y, "Next detector", formatIn(schedule.nextDetectorAt), colors.lightGray); y = y + 1
    TermUI.drawInfoLine(y, "Next AE", formatIn(schedule.nextAeAt), colors.lightGray); y = y + 1

    if y < h then
        TermUI.drawText(2, y + 1, "Last event: " .. tostring(self.lastEvent) .. " (" .. formatAge(self.lastEventAt) .. ")", colors.gray)
    end

    TermUI.drawStatusBar("Ctrl+T to terminate")
end

function Dashboard:run()
    TermUI.refreshSize()
    local timer = os.startTimer(1)

    while true do
        local event, p1 = os.pullEvent()
        if event == "collector_event" then
            self:recordEvent(p1 and p1.kind or "event")
        elseif event == "collector_dirty" then
            self.dirty = true
        elseif event == "term_resize" then
            TermUI.refreshSize()
            self.dirty = true
        elseif event == "timer" and p1 == timer then
            self.dirty = true
            timer = os.startTimer(1)
        end

        if self.dirty then
            self:render()
            self.dirty = false
        end
    end
end

return Dashboard
