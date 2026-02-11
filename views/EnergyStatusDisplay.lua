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
            maxHistory = width
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

    render = function(self)
        self.monitor.clear()

        -- Check if interface exists
        if not self.interface then
            self.monitor.setCursorPos(1, math.floor(self.height / 2) - 1)
            self.monitor.write("Energy Status")
            self.monitor.setCursorPos(1, math.floor(self.height / 2) + 1)
            self.monitor.write("No ME Bridge found")
            return
        end

        -- Get energy data
        local ok, energy = pcall(AEInterface.energy, self.interface)
        if not ok or not energy then
            self.monitor.setCursorPos(1, 1)
            self.monitor.write("Error fetching energy")
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

        -- Title
        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(1, 1)
        self.monitor.write("AE2 Energy Status")

        -- Percentage with color
        local pctStr = string.format("%.1f%%", percentage)
        self.monitor.setCursorPos(self.width - #pctStr + 1, 1)
        if percentage > 75 then
            self.monitor.setTextColor(colors.green)
        elseif percentage > 25 then
            self.monitor.setTextColor(colors.yellow)
        else
            self.monitor.setTextColor(colors.red)
        end
        self.monitor.write(pctStr)

        -- Stats line
        self.monitor.setTextColor(colors.lightGray)
        self.monitor.setCursorPos(1, 2)
        self.monitor.write(module.formatNumber(stored) .. " / " .. module.formatNumber(capacity) .. " AE")

        -- Usage
        self.monitor.setCursorPos(1, 3)
        self.monitor.setTextColor(colors.orange)
        self.monitor.write("Using: " .. module.formatNumber(usage) .. " AE/t")

        -- Draw energy bar (row 5)
        local barWidth = self.width - 2
        local filledWidth = math.floor(barWidth * percentage / 100)

        self.monitor.setCursorPos(1, 5)
        self.monitor.write("[")

        -- Filled portion
        if percentage > 75 then
            self.monitor.setBackgroundColor(colors.green)
        elseif percentage > 25 then
            self.monitor.setBackgroundColor(colors.yellow)
        else
            self.monitor.setBackgroundColor(colors.red)
        end

        for i = 1, filledWidth do
            self.monitor.write(" ")
        end

        -- Empty portion
        self.monitor.setBackgroundColor(colors.gray)
        for i = filledWidth + 1, barWidth do
            self.monitor.write(" ")
        end

        self.monitor.setBackgroundColor(colors.black)
        self.monitor.write("]")

        -- Draw history graph if we have room
        if self.height > 7 then
            self.monitor.setTextColor(colors.lightGray)
            self.monitor.setCursorPos(1, 7)
            self.monitor.write("History:")

            local graphHeight = self.height - 8
            local graphStartY = 8

            for x, pct in ipairs(self.history) do
                local barHeight = math.floor(graphHeight * pct / 100)
                local xPos = self.width - #self.history + x

                if xPos >= 1 then
                    -- Color based on percentage
                    if pct > 75 then
                        self.monitor.setBackgroundColor(colors.green)
                    elseif pct > 25 then
                        self.monitor.setBackgroundColor(colors.yellow)
                    else
                        self.monitor.setBackgroundColor(colors.red)
                    end

                    for y = 0, barHeight - 1 do
                        self.monitor.setCursorPos(xPos, self.height - y)
                        self.monitor.write(" ")
                    end
                end
            end
            self.monitor.setBackgroundColor(colors.black)
        end

        self.monitor.setTextColor(colors.white)
    end
}

return module
