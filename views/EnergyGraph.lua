-- EnergyGraph.lua
-- Displays AE2 network energy status with history graph
-- Configurable: warning threshold percentage

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')

return BaseView.custom({
    sleepTime = 1,

    configSchema = {
        {
            key = "warningBelow",
            type = "number",
            label = "Warning Below %",
            default = 25,
            min = 1,
            max = 99,
            presets = {10, 25, 50, 75}
        }
    },

    mount = function()
        return AEInterface.exists()
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil
        self.warningBelow = config.warningBelow or 25
        self.history = {}
        self.maxHistory = self.width
    end,

    getData = function(self)
        -- Check interface is available
        if not self.interface then return nil end

        -- Get energy data
        local energy = self.interface:energy()
        if not energy then return nil end

        local stored = energy.stored or 0
        local capacity = energy.capacity or 1
        local usage = energy.usage or 0
        local percentage = capacity > 0 and (stored / capacity * 100) or 0

        -- Record history
        MonitorHelpers.recordHistory(self.history, percentage, self.maxHistory)

        return {
            stored = stored,
            capacity = capacity,
            usage = usage,
            percentage = percentage,
            history = self.history
        }
    end,

    render = function(self, data)
        -- Determine color
        local barColor = colors.green
        if data.percentage <= self.warningBelow then
            barColor = colors.red
        elseif data.percentage <= self.warningBelow * 2 then
            barColor = colors.yellow
        end

        -- Row 1: Title and percentage
        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(1, 1)
        self.monitor.write("AE2 Energy")

        local pctStr = string.format("%.1f%%", data.percentage)
        self.monitor.setTextColor(barColor)
        self.monitor.setCursorPos(math.max(1, self.width - #pctStr + 1), 1)
        self.monitor.write(pctStr)

        -- Row 2: Stats
        self.monitor.setTextColor(colors.lightGray)
        local statsStr = Text.formatNumber(data.stored, 1) .. " / " .. Text.formatNumber(data.capacity, 1) .. " AE"
        self.monitor.setCursorPos(1, 2)
        self.monitor.write(Text.truncateMiddle(statsStr, self.width))

        -- Row 3: Usage
        self.monitor.setTextColor(colors.orange)
        local usageStr = "Using: " .. Text.formatNumber(data.usage, 1) .. " AE/t"
        self.monitor.setCursorPos(1, 3)
        self.monitor.write(Text.truncateMiddle(usageStr, self.width))

        -- Row 5: Energy bar
        if self.height >= 5 then
            MonitorHelpers.drawProgressBar(self.monitor, 1, 5, self.width, data.percentage, barColor, colors.gray, true)
        end

        -- History graph (if room)
        if self.height >= 9 then
            local graphStartY = 7
            local graphEndY = self.height - 1

            self.monitor.setTextColor(colors.gray)
            self.monitor.setCursorPos(1, graphStartY)
            self.monitor.write("History:")

            local warnPct = self.warningBelow
            MonitorHelpers.drawHistoryGraph(
                self.monitor,
                self.history,
                1,
                graphStartY + 1,
                graphEndY,
                100,
                function(val)
                    if val <= warnPct then return colors.red
                    elseif val <= warnPct * 2 then return colors.yellow
                    else return colors.green end
                end
            )
        end

        -- Bottom: warning threshold
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(1, self.height)
        self.monitor.write("Warn <" .. self.warningBelow .. "%")

        self.monitor.setTextColor(colors.white)
    end,

    errorMessage = "Error fetching energy"
})
