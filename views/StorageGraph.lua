-- StorageGraph.lua
-- Displays AE2 storage capacity as a graph over time
-- Configurable: storage type (items, fluids, both)

local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')

local module

module = {
    sleepTime = 1,

    configSchema = {
        {
            key = "storageType",
            type = "select",
            label = "Storage Type",
            options = {
                { value = "items", label = "Items" },
                { value = "fluids", label = "Fluids" },
                { value = "both", label = "Both (Total)" }
            },
            default = "items"
        }
    },

    new = function(monitor, config)
        config = config or {}
        local width, height = monitor.getSize()

        local self = {
            monitor = monitor,
            width = width,
            height = height,
            storageType = config.storageType or "items",
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
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No AE2 peripheral", colors.red)
            return
        end

        -- Get storage data
        local used, total = 0, 0

        if self.storageType == "items" or self.storageType == "both" then
            local ok, status = pcall(AEInterface.storage_status, self.interface)
            if ok and status then
                used = used + (status.usedItemStorage or 0)
                total = total + (status.totalItemStorage or 0)
            end
        end

        if self.storageType == "fluids" or self.storageType == "both" then
            local ok, fluidStatus = pcall(AEInterface.fluidStorage, self.interface)
            if ok and fluidStatus then
                used = used + (fluidStatus.used or 0)
                total = total + (fluidStatus.total or 0)
            end
        end

        local percentage = total > 0 and (used / total * 100) or 0

        -- Record history
        MonitorHelpers.recordHistory(self.history, percentage, self.maxHistory)

        -- Determine color
        local barColor = colors.green
        if percentage > 90 then
            barColor = colors.red
        elseif percentage > 75 then
            barColor = colors.orange
        elseif percentage > 50 then
            barColor = colors.yellow
        end

        -- Clear screen
        self.monitor.clear()

        -- Row 1: Title
        local typeLabel = self.storageType == "both" and "Storage" or (self.storageType:gsub("^%l", string.upper))
        local title = "AE2 " .. typeLabel .. " Capacity"
        MonitorHelpers.writeCentered(self.monitor, 1, Text.truncateMiddle(title, self.width), colors.white)

        -- Row 1 right: Current bytes
        local bytesStr = Text.formatNumber(used, 1) .. "B"
        self.monitor.setTextColor(colors.lightGray)
        self.monitor.setCursorPos(math.max(1, self.width - #bytesStr + 1), 1)
        self.monitor.write(bytesStr)

        -- Row 2: Percentage and total
        local pctStr = string.format("%.1f%%", percentage)
        self.monitor.setTextColor(barColor)
        self.monitor.setCursorPos(1, 2)
        self.monitor.write(pctStr)

        self.monitor.setTextColor(colors.gray)
        local totalStr = " / " .. Text.formatNumber(total, 1) .. "B"
        self.monitor.write(totalStr)

        -- Row 4: Progress bar
        if self.height >= 5 then
            MonitorHelpers.drawProgressBar(self.monitor, 1, 4, self.width, percentage, barColor, colors.gray, true)
        end

        -- History graph (if room)
        if self.height >= 8 then
            local graphStartY = 6
            local graphEndY = self.height - 1

            -- Label
            self.monitor.setTextColor(colors.gray)
            self.monitor.setCursorPos(1, graphStartY)
            self.monitor.write("History:")

            -- Draw graph
            MonitorHelpers.drawHistoryGraph(
                self.monitor,
                self.history,
                1,
                graphStartY + 1,
                graphEndY,
                100,  -- Max is 100%
                function(val, max)
                    if val > 90 then return colors.red
                    elseif val > 75 then return colors.orange
                    elseif val > 50 then return colors.yellow
                    else return colors.green end
                end
            )
        end

        -- Bottom: 0 label
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(1, self.height)
        self.monitor.write("0")

        self.monitor.setTextColor(colors.white)
    end
}

return module
