-- EnergyGraph.lua
-- Displays AE2 network energy status with history graph
-- Shows stored energy, input rate, usage rate, and net flow
-- Configurable: warning threshold percentage

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

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
        },
        {
            key = "showFlow",
            type = "select",
            label = "Show Flow",
            options = {
                { value = true, label = "Yes" },
                { value = false, label = "No" }
            },
            default = true
        }
    },

    mount = function()
        local ok, exists = pcall(function()
            return AEInterface and AEInterface.exists and AEInterface.exists()
        end)
        return ok and exists == true
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil
        self.warningBelow = config.warningBelow or 25
        self.showFlow = config.showFlow ~= false
        self.history = {}
        self.maxHistory = self.width
    end,

    getData = function(self)
        -- Lazy re-init: retry if host not yet discovered at init time
        if not self.interface then
            local ok, interface = pcall(AEInterface.new)
            self.interface = ok and interface or nil
        end
        if not self.interface then return nil end

        -- Get energy data
        local energy = self.interface:energy()
        if not energy then return nil end

        Yield.yield()

        local stored = energy.stored or 0
        local capacity = energy.capacity or 1
        local usage = energy.usage or 0
        local percentage = capacity > 0 and (stored / capacity * 100) or 0

        -- Get input rate
        local input = 0
        local inputOk = pcall(function()
            input = self.interface:getAverageEnergyInput() or 0
        end)
        if not inputOk then input = 0 end

        -- Calculate net flow
        local netFlow = input - usage

        -- Record history
        MonitorHelpers.recordHistory(self.history, percentage, self.maxHistory)

        return {
            stored = stored,
            capacity = capacity,
            input = input,
            usage = usage,
            netFlow = netFlow,
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

        -- Row 3: Energy flow (IN/OUT/NET)
        local row3Y = 3
        if self.showFlow then
            -- Input
            self.monitor.setTextColor(colors.lime)
            self.monitor.setCursorPos(1, row3Y)
            self.monitor.write("IN:")
            self.monitor.setTextColor(colors.white)
            self.monitor.write(Text.formatNumber(data.input, 0))

            -- Output
            local outX = math.floor(self.width / 2) - 2
            self.monitor.setTextColor(colors.red)
            self.monitor.setCursorPos(outX, row3Y)
            self.monitor.write("OUT:")
            self.monitor.setTextColor(colors.white)
            self.monitor.write(Text.formatNumber(data.usage, 0))
            row3Y = row3Y + 1

            -- Net flow
            self.monitor.setCursorPos(1, row3Y)
            if data.netFlow >= 0 then
                self.monitor.setTextColor(colors.lime)
                self.monitor.write("NET: +" .. Text.formatNumber(data.netFlow, 0) .. " AE/t")
            else
                self.monitor.setTextColor(colors.red)
                self.monitor.write("NET: " .. Text.formatNumber(data.netFlow, 0) .. " AE/t")
            end
            row3Y = row3Y + 1
        else
            -- Simple usage display
            self.monitor.setTextColor(colors.orange)
            local usageStr = "Using: " .. Text.formatNumber(data.usage, 1) .. " AE/t"
            self.monitor.setCursorPos(1, row3Y)
            self.monitor.write(Text.truncateMiddle(usageStr, self.width))
            row3Y = row3Y + 1
        end

        -- Energy bar
        local barY = row3Y + 1
        if self.height >= barY then
            MonitorHelpers.drawProgressBar(self.monitor, 1, barY, self.width, data.percentage, barColor, colors.gray, true)
        end

        -- History graph (if room)
        local graphStartY = barY + 2
        if self.height >= graphStartY + 3 then
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
