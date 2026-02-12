-- EnergyBalance.lua
-- Displays AE2 energy input vs output balance with trend indicator
-- Shows net energy flow (surplus/deficit) with history graph

local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

local module

module = {
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

    new = function(monitor, config)
        config = config or {}
        local width, height = monitor.getSize()

        local self = {
            monitor = monitor,
            width = width,
            height = height,
            warningDeficit = config.warningDeficit or 100,
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

        -- Get energy data (base methods from AEInterface)
        local ok, energy = pcall(function() return self.interface:energy() end)
        Yield.yield()
        if not ok or not energy then
            MonitorHelpers.writeCentered(self.monitor, 1, "Error fetching energy", colors.red)
            return
        end

        -- Get average input directly from bridge (not yet in AEInterface wrapper)
        local input = 0
        local inputOk = pcall(function()
            input = self.interface.bridge.getAverageEnergyInput() or 0
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
        local isSurplus = netBalance >= 0
        local isDeficit = netBalance < 0
        local isWarning = isDeficit and math.abs(netBalance) >= self.warningDeficit

        -- Record history (net balance)
        MonitorHelpers.recordHistory(self.history, netBalance, self.maxHistory)

        -- Determine balance color
        local balanceColor = colors.lime
        if isWarning then
            balanceColor = colors.red
        elseif isDeficit then
            balanceColor = colors.orange
        end

        -- Clear and render
        self.monitor.clear()

        -- Row 1: Title
        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(1, 1)
        self.monitor.write("Energy Balance")

        -- Row 2: Input rate
        self.monitor.setTextColor(colors.green)
        local inputStr = "IN:  " .. Text.formatNumber(input, 1) .. " AE/t"
        self.monitor.setCursorPos(1, 2)
        self.monitor.write(Text.truncateMiddle(inputStr, self.width))

        -- Row 3: Output rate
        self.monitor.setTextColor(colors.orange)
        local outputStr = "OUT: " .. Text.formatNumber(usage, 1) .. " AE/t"
        self.monitor.setCursorPos(1, 3)
        self.monitor.write(Text.truncateMiddle(outputStr, self.width))

        -- Row 4: Net balance with indicator
        self.monitor.setTextColor(balanceColor)
        local balanceStr
        if isSurplus then
            balanceStr = "+" .. Text.formatNumber(netBalance, 1) .. " AE/t"
        else
            balanceStr = Text.formatNumber(netBalance, 1) .. " AE/t"
        end
        
        local indicator = isSurplus and "^" or "v"
        balanceStr = indicator .. " " .. balanceStr

        self.monitor.setCursorPos(1, 4)
        self.monitor.write(Text.truncateMiddle(balanceStr, self.width))

        -- Row 5: Storage percentage bar
        if self.height >= 6 then
            local barColor = colors.green
            if percentage <= 25 then
                barColor = colors.red
            elseif percentage <= 50 then
                barColor = colors.yellow
            end

            MonitorHelpers.drawProgressBar(self.monitor, 1, 6, self.width, percentage, barColor, colors.gray, true)
            
            -- Show percentage on same row if room
            if self.width >= 12 then
                local pctStr = string.format("%.1f%%", percentage)
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
            local colorFn = function(val)
                if val >= 0 then
                    return colors.lime
                elseif math.abs(val) >= self.warningDeficit then
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
    end
}

return module
