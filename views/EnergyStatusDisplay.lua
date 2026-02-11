-- EnergyStatusDisplay.lua
-- Displays AE2 network energy status with visual bar
-- Supports: me_bridge (Advanced Peripherals)

local AEInterface = mpm('peripherals/AEInterface')

local module

module = {
    sleepTime = 1,

    new = function(monitor, config)
        local width, height = monitor.getSize()
        local self = {
            monitor = monitor,
            interface = nil,
            width = width,
            height = height,
            history = {},
            maxHistory = width,
            initialized = false
        }

        -- Try to create interface
        local ok, interface = pcall(AEInterface.new)
        if ok and interface then
            self.interface = interface
        end

        return self
    end,

    mount = function()
        local exists, pType = AEInterface.exists()
        -- Only mount if we have me_bridge (energy methods require it)
        return exists and pType == "me_bridge"
    end,

    formatNumber = function(num)
        if num >= 1000000000 then
            return string.format("%.1fG", num / 1000000000)
        elseif num >= 1000000 then
            return string.format("%.1fM", num / 1000000)
        elseif num >= 1000 then
            return string.format("%.1fK", num / 1000)
        else
            return tostring(math.floor(num))
        end
    end,

    -- Clear a single line by overwriting with spaces
    clearLine = function(self, y)
        self.monitor.setCursorPos(1, y)
        self.monitor.write(string.rep(" ", self.width))
    end,

    -- Write text at position, padding to clear old content
    writeAt = function(self, x, y, text, padWidth)
        self.monitor.setCursorPos(x, y)
        if padWidth then
            text = text .. string.rep(" ", math.max(0, padWidth - #text))
        end
        self.monitor.write(text)
    end,

    render = function(self)
        -- One-time initialization (clear screen once)
        if not self.initialized then
            self.monitor.clear()
            self.initialized = true
        end

        self.monitor.setBackgroundColor(colors.black)

        -- Check if interface exists
        if not self.interface then
            module.clearLine(self, math.floor(self.height / 2) - 1)
            module.clearLine(self, math.floor(self.height / 2))
            module.clearLine(self, math.floor(self.height / 2) + 1)
            self.monitor.setTextColor(colors.white)
            module.writeAt(self, 1, math.floor(self.height / 2) - 1, "Energy Status")
            module.writeAt(self, 1, math.floor(self.height / 2) + 1, "No ME Bridge found")
            return
        end

        -- Get energy data
        local ok, energy = pcall(AEInterface.energy, self.interface)
        if not ok or not energy then
            module.clearLine(self, 1)
            self.monitor.setTextColor(colors.red)
            module.writeAt(self, 1, 1, "Error fetching energy", self.width)
            return
        end

        local stored = energy.stored or 0
        local capacity = energy.capacity or 1
        local usage = energy.usage or 0
        local percentage = capacity > 0 and (stored / capacity * 100) or 0

        -- Record history
        table.insert(self.history, percentage)
        if #self.history > self.maxHistory then
            table.remove(self.history, 1)
        end

        -- Determine color based on percentage
        local barColor = colors.green
        if percentage <= 25 then
            barColor = colors.red
        elseif percentage <= 75 then
            barColor = colors.yellow
        end

        -- Row 1: Title and percentage
        self.monitor.setTextColor(colors.white)
        module.writeAt(self, 1, 1, "AE2 Energy Status", 20)

        local pctStr = string.format("%.1f%%", percentage)
        self.monitor.setTextColor(barColor)
        module.writeAt(self, self.width - #pctStr + 1, 1, pctStr)

        -- Row 2: Stats
        self.monitor.setTextColor(colors.lightGray)
        local statsStr = module.formatNumber(stored) .. " / " .. module.formatNumber(capacity) .. " AE"
        module.writeAt(self, 1, 2, statsStr, self.width)

        -- Row 3: Usage
        self.monitor.setTextColor(colors.orange)
        local usageStr = "Using: " .. module.formatNumber(usage) .. " AE/t"
        module.writeAt(self, 1, 3, usageStr, self.width)

        -- Row 5: Energy bar
        local barWidth = self.width - 2
        local filledWidth = math.floor(barWidth * percentage / 100)

        self.monitor.setCursorPos(1, 5)
        self.monitor.setTextColor(colors.white)
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.write("[")

        -- Filled portion
        self.monitor.setBackgroundColor(barColor)
        self.monitor.write(string.rep(" ", filledWidth))

        -- Empty portion
        self.monitor.setBackgroundColor(colors.gray)
        self.monitor.write(string.rep(" ", barWidth - filledWidth))

        self.monitor.setBackgroundColor(colors.black)
        self.monitor.write("]")

        -- History graph (if room)
        if self.height > 7 then
            -- Row 7: Label
            self.monitor.setTextColor(colors.lightGray)
            self.monitor.setBackgroundColor(colors.black)
            module.writeAt(self, 1, 7, "History:", self.width)

            local graphHeight = self.height - 8
            local graphStartY = 8

            -- Clear graph area first (only the columns we'll use)
            for y = graphStartY, self.height do
                self.monitor.setBackgroundColor(colors.black)
                module.clearLine(self, y)
            end

            -- Draw graph bars
            for i, pct in ipairs(self.history) do
                local barHeight = math.max(0, math.floor(graphHeight * pct / 100))
                local xPos = self.width - #self.history + i

                if xPos >= 1 and barHeight > 0 then
                    -- Determine bar color
                    local histColor = colors.green
                    if pct <= 25 then
                        histColor = colors.red
                    elseif pct <= 75 then
                        histColor = colors.yellow
                    end

                    self.monitor.setBackgroundColor(histColor)
                    for y = 0, barHeight - 1 do
                        local yPos = self.height - y
                        if yPos >= graphStartY then
                            self.monitor.setCursorPos(xPos, yPos)
                            self.monitor.write(" ")
                        end
                    end
                end
            end
        end

        -- Reset colors
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)
    end
}

return module
