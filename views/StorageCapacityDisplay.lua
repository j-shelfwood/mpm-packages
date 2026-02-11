-- StorageCapacityDisplay.lua
-- Displays AE2 storage capacity as a graph over time
-- Supports: me_bridge (Advanced Peripherals), merequester:requester

local AEInterface = mpm('peripherals/AEInterface')

local module

module = {
    sleepTime = 1,

    new = function(monitor)
        local self = {
            monitor = monitor,
            interface = AEInterface.new(), -- Auto-detects peripheral
            WIDTH = monitor.getSize(),
            HEIGHT = select(2, monitor.getSize()),
            MAX_DATA_POINTS = select(1, monitor.getSize()),
            storageData = {},
            TITLE = "AE2 Capacity Status"
        }
        return self
    end,

    mount = function()
        return AEInterface.exists()
    end,

    recordStorageUsage = function(self)
        local status = AEInterface.storage_status(self.interface)
        local usedStorage = status.usedItemStorage
        table.insert(self.storageData, usedStorage)
        if #self.storageData > self.MAX_DATA_POINTS then
            table.remove(self.storageData, 1)
        end
    end,

    calculateGraphData = function(self)
        local status = AEInterface.storage_status(self.interface)
        local totalStorage = status.totalItemStorage
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
        local heights = module.calculateGraphData(self)
        local status = AEInterface.storage_status(self.interface)

        self.monitor.clear()

        -- Title
        local titleStartX = math.floor((self.WIDTH - #self.TITLE) / 2) + 1
        self.monitor.setCursorPos(titleStartX, 1)
        self.monitor.write(self.TITLE)

        -- Current bytes used
        local currentBytes = status.usedItemStorage
        local bytesStr = tostring(currentBytes) .. "B"
        self.monitor.setCursorPos(self.WIDTH - #bytesStr + 1, 1)
        self.monitor.write(bytesStr)

        -- Total capacity label
        self.monitor.setCursorPos(1, 2)
        self.monitor.write(tostring(status.totalItemStorage))

        -- Zero label
        self.monitor.setCursorPos(1, self.HEIGHT)
        self.monitor.write("0")

        -- Draw graph columns
        for x, height in ipairs(heights) do
            local columnPosition = self.WIDTH - #heights + x
            self.monitor.setBackgroundColor(colors.pink)
            for y = self.HEIGHT, self.HEIGHT - height + 2, -1 do
                self.monitor.setCursorPos(columnPosition, y)
                self.monitor.write(" ")
            end
        end
        self.monitor.setBackgroundColor(colors.black)
    end,

    render = function(self)
        module.recordStorageUsage(self)
        module.drawGraph(self)
    end
}

return module
