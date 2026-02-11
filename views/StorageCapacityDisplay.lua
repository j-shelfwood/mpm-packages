-- StorageCapacityDisplay.lua
-- Displays AE2 storage capacity as a graph over time
-- Supports: me_bridge (Advanced Peripherals), merequester:requester

local AEInterface = mpm('peripherals/AEInterface')

local module

module = {
    sleepTime = 1,

    new = function(monitor, config)
        local width, height = monitor.getSize()
        local self = {
            monitor = monitor,
            interface = nil,
            WIDTH = width,
            HEIGHT = height,
            MAX_DATA_POINTS = width,
            storageData = {},
            TITLE = "AE2 Capacity Status",
            initialized = false
        }

        -- Try to create interface (may fail if no peripheral)
        local ok, interface = pcall(AEInterface.new)
        if ok and interface then
            self.interface = interface
        end

        return self
    end,

    mount = function()
        return AEInterface.exists()
    end,

    -- Clear a single line by overwriting with spaces
    clearLine = function(self, y)
        self.monitor.setCursorPos(1, y)
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.write(string.rep(" ", self.WIDTH))
    end,

    -- Write text at position with optional padding
    writeAt = function(self, x, y, text, padWidth)
        self.monitor.setCursorPos(x, y)
        if padWidth then
            text = text .. string.rep(" ", math.max(0, padWidth - #text))
        end
        self.monitor.write(text)
    end,

    recordStorageUsage = function(self)
        if not self.interface then
            return
        end

        local ok, status = pcall(AEInterface.storage_status, self.interface)
        if not ok or not status then
            return
        end

        local usedStorage = status.usedItemStorage or 0
        table.insert(self.storageData, usedStorage)
        if #self.storageData > self.MAX_DATA_POINTS then
            table.remove(self.storageData, 1)
        end
    end,

    calculateGraphData = function(self)
        if not self.interface then
            return {}, 0
        end

        local ok, status = pcall(AEInterface.storage_status, self.interface)
        if not ok or not status then
            return {}, 0
        end

        local totalStorage = status.totalItemStorage or 0
        local heights = {}

        if totalStorage == 0 then
            return heights, 0
        end

        for _, usage in ipairs(self.storageData) do
            local height = math.floor((usage / totalStorage) * (self.HEIGHT - 2))
            table.insert(heights, height)
        end
        return heights, totalStorage
    end,

    render = function(self)
        -- One-time initialization
        if not self.initialized then
            self.monitor.clear()
            self.initialized = true
        end

        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)

        -- Check if interface exists
        if not self.interface then
            local titleStartX = math.floor((self.WIDTH - #self.TITLE) / 2) + 1
            module.clearLine(self, 1)
            module.writeAt(self, titleStartX, 1, self.TITLE)
            module.clearLine(self, math.floor(self.HEIGHT / 2))
            module.writeAt(self, 1, math.floor(self.HEIGHT / 2), "No AE2 peripheral found")
            return
        end

        -- Record new data point
        module.recordStorageUsage(self)

        local heights, totalStorage = module.calculateGraphData(self)
        local ok, status = pcall(AEInterface.storage_status, self.interface)

        if not ok or not status then
            module.clearLine(self, 1)
            module.writeAt(self, 1, 1, "Error getting storage status", self.WIDTH)
            return
        end

        -- Row 1: Title
        local titleStartX = math.floor((self.WIDTH - #self.TITLE) / 2) + 1
        module.clearLine(self, 1)
        module.writeAt(self, titleStartX, 1, self.TITLE)

        -- Handle zero capacity
        if (status.totalItemStorage or 0) == 0 then
            module.clearLine(self, math.floor(self.HEIGHT / 2))
            module.writeAt(self, 1, math.floor(self.HEIGHT / 2), "No storage capacity")
            return
        end

        -- Current bytes used (right side of row 1)
        local currentBytes = status.usedItemStorage or 0
        local bytesStr = tostring(currentBytes) .. "B"
        self.monitor.setTextColor(colors.lightGray)
        module.writeAt(self, math.max(1, self.WIDTH - #bytesStr + 1), 1, bytesStr)

        -- Row 2: Total capacity label
        module.clearLine(self, 2)
        self.monitor.setTextColor(colors.gray)
        module.writeAt(self, 1, 2, tostring(status.totalItemStorage or 0))

        -- Bottom row: Zero label
        module.clearLine(self, self.HEIGHT)
        module.writeAt(self, 1, self.HEIGHT, "0")

        -- Clear graph area (rows 3 to HEIGHT-1)
        for y = 3, self.HEIGHT - 1 do
            module.clearLine(self, y)
        end

        -- Draw graph columns
        if #heights > 0 then
            -- Calculate percentage for color
            local percentage = (currentBytes / (status.totalItemStorage or 1)) * 100
            local barColor = colors.green
            if percentage > 90 then
                barColor = colors.red
            elseif percentage > 75 then
                barColor = colors.orange
            elseif percentage > 50 then
                barColor = colors.yellow
            end

            self.monitor.setBackgroundColor(barColor)

            for x, height in ipairs(heights) do
                local columnPosition = self.WIDTH - #heights + x
                if columnPosition >= 1 and height > 0 then
                    for y = self.HEIGHT - 1, math.max(3, self.HEIGHT - height), -1 do
                        self.monitor.setCursorPos(columnPosition, y)
                        self.monitor.write(" ")
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
