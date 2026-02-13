-- EnergyFlow.lua
-- ME network energy flow visualization
-- Shows input vs output rates and net energy balance
-- Includes trend indicator for energy gain/drain

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')

-- Draw a horizontal bar graph
local function drawBar(monitor, x, y, width, percent, color)
    local filled = math.floor(width * math.min(1, math.max(0, percent)))
    monitor.setCursorPos(x, y)
    monitor.setBackgroundColor(color)
    monitor.write(string.rep(" ", filled))
    monitor.setBackgroundColor(colors.gray)
    monitor.write(string.rep(" ", width - filled))
    monitor.setBackgroundColor(colors.black)
end

-- Get trend arrow based on net flow
local function getTrendIndicator(netFlow)
    if netFlow > 10 then
        return "++", colors.lime
    elseif netFlow > 0 then
        return "+", colors.lime
    elseif netFlow < -10 then
        return "--", colors.red
    elseif netFlow < 0 then
        return "-", colors.red
    else
        return "=", colors.yellow
    end
end

return BaseView.custom({
    sleepTime = 1,  -- Fast refresh for real-time flow data

    configSchema = {},

    mount = function()
        return AEInterface.exists()
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil

        -- History for smoothing/trend
        self.history = {}
        self.maxHistory = 10
    end,

    getData = function(self)
        if not self.interface then return nil end

        local data = {}

        -- Energy stats
        local energy = self.interface:energy()
        data.stored = energy.stored or 0
        data.capacity = energy.capacity or 0
        data.usage = energy.usage or 0  -- Output/consumption

        -- Input rate (requires ME Bridge method)
        data.input = self.interface:getAverageEnergyInput() or 0

        -- Calculate net flow
        data.netFlow = data.input - data.usage

        -- Store in history for trend calculation
        table.insert(self.history, data.netFlow)
        if #self.history > self.maxHistory then
            table.remove(self.history, 1)
        end

        -- Calculate average trend
        local sum = 0
        for _, v in ipairs(self.history) do
            sum = sum + v
        end
        data.avgFlow = sum / #self.history

        -- Calculate fill percentage
        data.fillPercent = data.capacity > 0 and (data.stored / data.capacity) or 0

        -- Estimate time to full/empty
        if data.avgFlow > 0 then
            local remaining = data.capacity - data.stored
            data.timeToFull = remaining / data.avgFlow / 20  -- Convert ticks to seconds
            data.timeToEmpty = nil
        elseif data.avgFlow < 0 then
            data.timeToFull = nil
            data.timeToEmpty = data.stored / math.abs(data.avgFlow) / 20
        else
            data.timeToFull = nil
            data.timeToEmpty = nil
        end

        return data
    end,

    render = function(self, data)
        local y = 1

        -- Title
        self.monitor.setCursorPos(1, y)
        self.monitor.setTextColor(colors.cyan)
        self.monitor.write("ENERGY FLOW")
        y = y + 2

        -- Current energy level
        self.monitor.setCursorPos(1, y)
        self.monitor.setTextColor(colors.white)
        self.monitor.write("Stored: ")
        self.monitor.setTextColor(colors.yellow)
        self.monitor.write(Text.formatNumber(data.stored, 0))
        self.monitor.setTextColor(colors.gray)
        self.monitor.write(" / " .. Text.formatNumber(data.capacity, 0))
        y = y + 1

        -- Energy bar
        local barWidth = math.min(self.width, 20)
        local fillColor = colors.lime
        if data.fillPercent < 0.2 then
            fillColor = colors.red
        elseif data.fillPercent < 0.5 then
            fillColor = colors.yellow
        end
        drawBar(self.monitor, 1, y, barWidth, data.fillPercent, fillColor)

        -- Percentage on bar
        local percentStr = math.floor(data.fillPercent * 100) .. "%"
        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(barWidth + 2, y)
        self.monitor.write(percentStr)
        y = y + 2

        -- Input rate
        self.monitor.setCursorPos(1, y)
        self.monitor.setTextColor(colors.lime)
        self.monitor.write("IN  ")
        self.monitor.setTextColor(colors.white)
        self.monitor.write(Text.formatNumber(data.input, 1) .. " AE/t")
        y = y + 1

        -- Output rate
        self.monitor.setCursorPos(1, y)
        self.monitor.setTextColor(colors.red)
        self.monitor.write("OUT ")
        self.monitor.setTextColor(colors.white)
        self.monitor.write(Text.formatNumber(data.usage, 1) .. " AE/t")
        y = y + 2

        -- Net flow with trend indicator
        local trendChar, trendColor = getTrendIndicator(data.avgFlow)
        self.monitor.setCursorPos(1, y)
        self.monitor.setTextColor(colors.white)
        self.monitor.write("NET ")
        self.monitor.setTextColor(trendColor)

        local netStr = ""
        if data.netFlow >= 0 then
            netStr = "+" .. Text.formatNumber(data.netFlow, 1)
        else
            netStr = Text.formatNumber(data.netFlow, 1)
        end
        self.monitor.write(netStr .. " AE/t ")
        self.monitor.write(trendChar)
        y = y + 2

        -- Time estimate
        if self.height >= y + 1 then
            self.monitor.setCursorPos(1, y)
            self.monitor.setTextColor(colors.gray)

            if data.timeToFull then
                local minutes = math.floor(data.timeToFull / 60)
                local seconds = math.floor(data.timeToFull % 60)
                if minutes > 0 then
                    self.monitor.write("Full in " .. minutes .. "m " .. seconds .. "s")
                else
                    self.monitor.write("Full in " .. seconds .. "s")
                end
            elseif data.timeToEmpty then
                local minutes = math.floor(data.timeToEmpty / 60)
                local seconds = math.floor(data.timeToEmpty % 60)
                if minutes > 60 then
                    self.monitor.write("Empty in " .. math.floor(minutes/60) .. "h")
                elseif minutes > 0 then
                    self.monitor.write("Empty in " .. minutes .. "m " .. seconds .. "s")
                else
                    self.monitor.write("Empty in " .. seconds .. "s")
                end
            else
                self.monitor.write("Stable")
            end
        end

        self.monitor.setTextColor(colors.white)
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No ME Network", colors.red)
    end,

    emptyMessage = "No ME Network",
    errorMessage = "Energy Flow Error"
})
