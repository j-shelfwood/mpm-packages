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
            TITLE = "AE2 Capacity Status"
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
            return {}
        end

        local ok, status = pcall(AEInterface.storage_status, self.interface)
        if not ok or not status then
            return {}
        end

        local totalStorage = status.totalItemStorage or 0
        local heights = {}

        if totalStorage == 0 then
            return heights
        end

        for _, usage in ipairs(self.storageData) do
            local height = math.floor((usage / totalStorage) * (self.HEIGHT - 1))
            table.insert(heights, height)
        end
        return heights
    end,

    drawGraph = function(self)
        self.monitor.clear()

        -- Check if interface exists
        if not self.interface then
            local titleStartX = math.floor((self.WIDTH - #self.TITLE) / 2) + 1
            self.monitor.setCursorPos(titleStartX, 1)
            self.monitor.write(self.TITLE)
            self.monitor.setCursorPos(1, math.floor(self.HEIGHT / 2))
            self.monitor.write("No AE2 peripheral found")
            return
        end

        local heights = module.calculateGraphData(self)
        local ok, status = pcall(AEInterface.storage_status, self.interface)

        if not ok or not status then
            self.monitor.setCursorPos(1, 1)
            self.monitor.write("Error getting storage status")
            return
        end

        -- Title
        local titleStartX = math.floor((self.WIDTH - #self.TITLE) / 2) + 1
        self.monitor.setCursorPos(titleStartX, 1)
        self.monitor.write(self.TITLE)

        -- Handle zero capacity
        if (status.totalItemStorage or 0) == 0 then
            self.monitor.setCursorPos(1, math.floor(self.HEIGHT / 2))
            self.monitor.write("No storage capacity")
            return
        end

        -- Current bytes used
        local currentBytes = status.usedItemStorage or 0
        local bytesStr = tostring(currentBytes) .. "B"
        self.monitor.setCursorPos(math.max(1, self.WIDTH - #bytesStr + 1), 1)
        self.monitor.write(bytesStr)

        -- Total capacity label
        self.monitor.setCursorPos(1, 2)
        self.monitor.write(tostring(status.totalItemStorage or 0))

        -- Zero label
        self.monitor.setCursorPos(1, self.HEIGHT)
        self.monitor.write("0")

        -- Draw graph columns
        if #heights > 0 then
            for x, height in ipairs(heights) do
                local columnPosition = self.WIDTH - #heights + x
                self.monitor.setBackgroundColor(colors.pink)
                for y = self.HEIGHT, math.max(2, self.HEIGHT - height + 2), -1 do
                    self.monitor.setCursorPos(columnPosition, y)
                    self.monitor.write(" ")
                end
            end
            self.monitor.setBackgroundColor(colors.black)
        end
    end,

    render = function(self)
        module.recordStorageUsage(self)
        module.drawGraph(self)
    end
}

return module
