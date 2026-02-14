-- ChangesRenderer.lua
-- Render functions for ChangesFactory views
-- Extracted from ChangesFactory.lua for maintainability

local MonitorHelpers = mpm('utils/MonitorHelpers')
local Text = mpm('utils/Text')
local DataHandler = mpm('views/factories/ChangesDataHandler')

local ChangesRenderer = {}

-- Render error state
function ChangesRenderer.renderError(self, data, cfg)
    MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), data.error, colors.red)
end

-- Render waiting state
function ChangesRenderer.renderWaiting(self, cfg)
    MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, cfg.name .. " Changes", colors.white)
    MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Waiting for data...", colors.gray)
end

-- Render baseline captured state
function ChangesRenderer.renderBaselineCaptured(self, data, cfg)
    MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, cfg.name .. " Changes", colors.white)
    MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Baseline: " .. data.baselineCount .. " " .. cfg.name:lower() .. "s", colors.lime)
    DataHandler.drawTimerBar(self.monitor, self.height, self.width, 0, self.periodSeconds, cfg.barColor)
end

-- Render period reset state
function ChangesRenderer.renderPeriodReset(self, data, cfg)
    MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Period Reset", colors.orange)
    MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "New baseline: " .. data.baselineCount .. " " .. cfg.name:lower() .. "s", colors.gray)
    DataHandler.drawTimerBar(self.monitor, self.height, self.width, 0, self.periodSeconds, cfg.barColor)
end

-- Render no changes state
function ChangesRenderer.renderNoChanges(self, data, cfg)
    MonitorHelpers.writeCentered(self.monitor, 1, cfg.name .. " Changes", cfg.titleColor)
    local centerY = math.floor(self.height / 2)
    MonitorHelpers.writeCentered(self.monitor, centerY - 1, "No changes detected", colors.gray)
    local infoStr = "Baseline: " .. data.baselineCount .. " | Current: " .. data.currentCount
    MonitorHelpers.writeCentered(self.monitor, centerY + 1, Text.truncateMiddle(infoStr, self.width - 2), colors.lightGray)
    DataHandler.drawTimerBar(self.monitor, self.height, self.width, data.elapsed, self.periodSeconds, cfg.barColor)
end

-- Render header overlay
function ChangesRenderer.renderHeader(self, data, cfg, remaining)
    self.monitor.setBackgroundColor(colors.black)
    self.monitor.setCursorPos(1, 1)
    self.monitor.clearLine()

    self.monitor.setTextColor(cfg.titleColor)
    self.monitor.setCursorPos(1, 1)
    self.monitor.write(cfg.name .. "s")

    self.monitor.setTextColor(colors.lightGray)
    self.monitor.write(" (" .. #data.changes .. ")")

    local timeStr = remaining .. "s"
    self.monitor.setTextColor(colors.gray)
    self.monitor.setCursorPos(math.max(1, self.width - #timeStr + 1), 1)
    self.monitor.write(timeStr)
end

-- Render summary row
function ChangesRenderer.renderSummary(self, data, cfg)
    if self.height < 8 then return end

    self.monitor.setCursorPos(1, 2)
    self.monitor.clearLine()

    if data.totalGains > 0 then
        self.monitor.setTextColor(colors.lime)
        self.monitor.write("+" .. Text.formatNumber(data.totalGains / cfg.unitDivisor, 1) .. cfg.unitLabel)
    end

    if data.totalLosses > 0 then
        if data.totalGains > 0 then
            self.monitor.setTextColor(colors.gray)
            self.monitor.write(" ")
        end
        self.monitor.setTextColor(colors.red)
        self.monitor.write("-" .. Text.formatNumber(data.totalLosses / cfg.unitDivisor, 1) .. cfg.unitLabel)
    end
end

return ChangesRenderer
