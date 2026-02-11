-- EnergyGraph.lua
-- Displays AE2 network energy status with history graph
-- Configurable: warning threshold percentage

local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')

local module

module = {
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

    new = function(monitor, config)
        config = config or {}
        local width, height = monitor.getSize()

        local self = {
            monitor = monitor,
            width = width,
            height = height,
            warningBelow = config.warningBelow or 25,
            interface = nil,
            history = {},
            maxHistory = width,
            initialized = false
        }

        local ok, interface = pcall(AEInterface.new)
        if ok and interface then
            self.interface = interface
        end

        return self
    end,

    mount = function()
        return AEInterface.exists()
    end,

    render = function(self)
        if not self.initialized then
            self.monitor.clear()
            self.initialized = true
        end

        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)

        if not self.interface then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No ME Bridge", colors.red)
            return
        end

        -- Get energy data
        local ok, energy = pcall(function() return self.interface:energy() end)
        if not ok or not energy then
            MonitorHelpers.writeCentered(self.monitor, 1, "Error fetching energy", colors.red)
            return
        end

        local stored = energy.stored or 0
        local capacity = energy.capacity or 1
        local usage = energy.usage or 0
        local percentage = capacity > 0 and (stored / capacity * 100) or 0

        -- Record history
        MonitorHelpers.recordHistory(self.history, percentage, self.maxHistory)

        -- Determine color
        local barColor = colors.green
        if percentage <= self.warningBelow then
            barColor = colors.red
        elseif percentage <= self.warningBelow * 2 then
            barColor = colors.yellow
        end

        -- Clear and render
        self.monitor.clear()

        -- Row 1: Title and percentage
        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(1, 1)
        self.monitor.write("AE2 Energy")

        local pctStr = string.format("%.1f%%", percentage)
        self.monitor.setTextColor(barColor)
        self.monitor.setCursorPos(math.max(1, self.width - #pctStr + 1), 1)
        self.monitor.write(pctStr)

        -- Row 2: Stats
        self.monitor.setTextColor(colors.lightGray)
        local statsStr = Text.formatNumber(stored, 1) .. " / " .. Text.formatNumber(capacity, 1) .. " AE"
        self.monitor.setCursorPos(1, 2)
        self.monitor.write(Text.truncateMiddle(statsStr, self.width))

        -- Row 3: Usage
        self.monitor.setTextColor(colors.orange)
        local usageStr = "Using: " .. Text.formatNumber(usage, 1) .. " AE/t"
        self.monitor.setCursorPos(1, 3)
        self.monitor.write(Text.truncateMiddle(usageStr, self.width))

        -- Row 5: Energy bar
        if self.height >= 5 then
            MonitorHelpers.drawProgressBar(self.monitor, 1, 5, self.width, percentage, barColor, colors.gray, true)
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
    end
}

return module
