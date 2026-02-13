-- EnergyBalance.lua
-- Displays AE2 energy input vs output balance with trend indicator
-- Shows net energy flow (surplus/deficit) with history graph

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

return BaseView.custom({
    sleepTime = 1,

    configSchema = {
        {
            key = "warningDeficit",
            type = "number",
            label = "Warning Deficit AE/t",
            default = 100,
            min = 1,
            max = 10000,
            presets = {10, 50, 100, 500, 1000}
        }
    },

    mount = function()
        return AEInterface.exists()
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil
        self.warningDeficit = config.warningDeficit or 100
        self.history = {}
        self.maxHistory = self.width
    end,

    getData = function(self)
        -- Check interface is available
        if not self.interface then return nil end

        -- Get energy data (base methods from AEInterface)
        local energy = self.interface:energy()
        if not energy then return nil end

        Yield.yield()

        -- Get average input
        local input = 0
        local inputOk = pcall(function()
            input = self.interface:getAverageEnergyInput() or 0
        end)

        Yield.yield()

        if not inputOk then
            input = 0
        end

        local stored = energy.stored or 0
        local capacity = energy.capacity or 1
        local usage = energy.usage or 0
        local percentage = capacity > 0 and (stored / capacity * 100) or 0

        -- Calculate net balance
        local netBalance = input - usage

        -- Record history (net balance)
        MonitorHelpers.recordHistory(self.history, netBalance, self.maxHistory)

        return {
            input = input,
            stored = stored,
            capacity = capacity,
            usage = usage,
            percentage = percentage,
            netBalance = netBalance,
            history = self.history
        }
    end,

    render = function(self, data)
        local isSurplus = data.netBalance >= 0
        local isDeficit = data.netBalance < 0
        local isWarning = isDeficit and math.abs(data.netBalance) >= self.warningDeficit

        -- Determine balance color
        local balanceColor = colors.lime
        if isWarning then
            balanceColor = colors.red
        elseif isDeficit then
            balanceColor = colors.orange
        end

        -- Row 1: Title
        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(1, 1)
        self.monitor.write("Energy Balance")

        -- Row 2: Input rate
        self.monitor.setTextColor(colors.green)
        local inputStr = "IN:  " .. Text.formatNumber(data.input, 1) .. " AE/t"
        self.monitor.setCursorPos(1, 2)
        self.monitor.write(Text.truncateMiddle(inputStr, self.width))

        -- Row 3: Output rate
        self.monitor.setTextColor(colors.orange)
        local outputStr = "OUT: " .. Text.formatNumber(data.usage, 1) .. " AE/t"
        self.monitor.setCursorPos(1, 3)
        self.monitor.write(Text.truncateMiddle(outputStr, self.width))

        -- Row 4: Net balance with indicator
        self.monitor.setTextColor(balanceColor)
        local balanceStr
        if isSurplus then
            balanceStr = "+" .. Text.formatNumber(data.netBalance, 1) .. " AE/t"
        else
            balanceStr = Text.formatNumber(data.netBalance, 1) .. " AE/t"
        end

        local indicator = isSurplus and "^" or "v"
        balanceStr = indicator .. " " .. balanceStr

        self.monitor.setCursorPos(1, 4)
        self.monitor.write(Text.truncateMiddle(balanceStr, self.width))

        -- Row 5: Storage percentage bar
        if self.height >= 6 then
            local barColor = colors.green
            if data.percentage <= 25 then
                barColor = colors.red
            elseif data.percentage <= 50 then
                barColor = colors.yellow
            end

            MonitorHelpers.drawProgressBar(self.monitor, 1, 6, self.width, data.percentage, barColor, colors.gray, true)

            -- Show percentage on same row if room
            if self.width >= 12 then
                local pctStr = string.format("%.1f%%", data.percentage)
                self.monitor.setTextColor(colors.white)
                self.monitor.setCursorPos(math.max(1, self.width - #pctStr + 1), 5)
                self.monitor.write(pctStr)
            end
        end

        -- History graph (if room)
        if self.height >= 10 then
            local graphStartY = 8
            local graphEndY = self.height - 1

            self.monitor.setTextColor(colors.gray)
            self.monitor.setCursorPos(1, graphStartY)
            self.monitor.write("Balance History:")

            -- Find max absolute value for scaling (ensure positive scale)
            local maxAbsValue = 1
            for _, v in ipairs(self.history) do
                local absV = math.abs(v)
                if absV > maxAbsValue then
                    maxAbsValue = absV
                end
            end

            -- Color function: green for positive, red/orange for negative
            local warningDeficit = self.warningDeficit
            local colorFn = function(val)
                if val >= 0 then
                    return colors.lime
                elseif math.abs(val) >= warningDeficit then
                    return colors.red
                else
                    return colors.orange
                end
            end

            -- Draw centered graph (0 in middle)
            local graphHeight = graphEndY - graphStartY
            local midY = graphStartY + math.floor(graphHeight / 2)

            -- Clear graph area
            self.monitor.setBackgroundColor(colors.black)
            for y = graphStartY + 1, graphEndY do
                self.monitor.setCursorPos(1, y)
                self.monitor.write(string.rep(" ", self.width))
            end

            -- Draw zero line
            self.monitor.setBackgroundColor(colors.gray)
            self.monitor.setCursorPos(1, midY)
            self.monitor.write(string.rep(" ", math.min(#self.history, self.width)))

            -- Draw bars
            for i, value in ipairs(self.history) do
                if i <= self.width then
                    local barColor = colorFn(value)
                    local barHeight = math.floor((math.abs(value) / maxAbsValue) * (graphHeight / 2))

                    if barHeight > 0 and value ~= 0 then
                        self.monitor.setBackgroundColor(barColor)

                        if value >= 0 then
                            -- Positive: draw upward from midY
                            for dy = 1, math.min(barHeight, midY - graphStartY - 1) do
                                local drawY = midY - dy
                                self.monitor.setCursorPos(i, drawY)
                                self.monitor.write(" ")
                            end
                        else
                            -- Negative: draw downward from midY
                            for dy = 1, math.min(barHeight, graphEndY - midY) do
                                local drawY = midY + dy
                                self.monitor.setCursorPos(i, drawY)
                                self.monitor.write(" ")
                            end
                        end
                    end
                end
            end

            self.monitor.setBackgroundColor(colors.black)
        end

        -- Bottom: warning threshold indicator
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(1, self.height)
        local warningStr = "Warn: " .. Text.formatNumber(self.warningDeficit, 0) .. " AE/t deficit"
        self.monitor.write(Text.truncateMiddle(warningStr, self.width))

        self.monitor.setTextColor(colors.white)
    end,

    renderEmpty = function(self)
        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(1, 1)
        self.monitor.write("Energy Balance")

        self.monitor.setTextColor(colors.gray)
        local midY = math.floor(self.height / 2)
        local msg = "No energy data"
        local x = math.max(1, math.floor((self.width - #msg) / 2) + 1)
        self.monitor.setCursorPos(x, midY)
        self.monitor.write(msg)
    end,

    errorMessage = "Error fetching energy"
})
