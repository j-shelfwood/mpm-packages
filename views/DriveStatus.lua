-- DriveStatus.lua
-- Displays grid overview of all AE2 ME Drives
-- Shows drive status, cell count, and storage usage

local AEInterface = mpm('peripherals/AEInterface')
local GridDisplay = mpm('utils/GridDisplay')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

local module

module = {
    sleepTime = 5,

    configSchema = {
        {
            key = "showEmpty",
            type = "select",
            label = "Show Empty Drives",
            options = {
                { value = true, label = "Yes" },
                { value = false, label = "No" }
            },
            default = true
        }
    },

    new = function(monitor, config)
        config = config or {}
        local width, height = monitor.getSize()

        local self = {
            monitor = monitor,
            width = width,
            height = height,
            showEmpty = config.showEmpty ~= false,
            interface = nil,
            display = GridDisplay.new(monitor),
            initialized = false
        }

        local ok, interface = pcall(AEInterface.new)
        if ok and interface then
            self.interface = interface
        end

        return self
    end,

    mount = function()
        local exists, pType = AEInterface.exists()
        return exists and pType == "me_bridge"
    end,

    formatDrive = function(driveData)
        local lines = {}
        local lineColors = {}

        -- Get drive stats
        local cells = driveData.cells or {}
        local cellCount = #cells
        local usedBytes = driveData.usedBytes or 0
        local totalBytes = driveData.totalBytes or 0
        local hasCells = cellCount > 0

        -- Calculate percentage
        local percentage = 0
        if totalBytes > 0 then
            percentage = (usedBytes / totalBytes) * 100
        end

        -- Determine status color
        local statusColor = colors.gray
        if hasCells then
            if percentage >= 90 then
                statusColor = colors.red
            elseif percentage >= 75 then
                statusColor = colors.orange
            elseif percentage >= 50 then
                statusColor = colors.yellow
            else
                statusColor = colors.lime
            end
        end

        -- Line 1: Cell count
        local cellText = cellCount .. " cell" .. (cellCount ~= 1 and "s" or "")
        if cellCount == 0 then
            cellText = "Empty"
        end
        table.insert(lines, cellText)
        table.insert(lineColors, colors.white)

        -- Line 2: Status indicator
        local statusText
        if cellCount == 0 then
            statusText = "----"
        else
            statusText = string.format("%.0f%%", percentage)
        end
        table.insert(lines, statusText)
        table.insert(lineColors, statusColor)

        -- Line 3: Storage (if has cells)
        if hasCells then
            local usedStr = Text.formatNumber(usedBytes, 1) .. "B"
            table.insert(lines, usedStr)
            table.insert(lineColors, colors.gray)
        end

        return {
            lines = lines,
            colors = lineColors
        }
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

        -- Get all drives
        local ok, drives = pcall(function() return self.interface.bridge.getDrives() end)
        Yield.yield()
        if not ok or not drives then
            MonitorHelpers.writeCentered(self.monitor, 1, "Error fetching drives", colors.red)
            return
        end

        -- Filter empty drives if configured
        local filteredDrives = {}
        for _, drive in ipairs(drives) do
            local cells = drive.cells or {}
            local hasCells = #cells > 0
            if self.showEmpty or hasCells then
                table.insert(filteredDrives, drive)
            end
        end

        -- Handle no drives
        if #filteredDrives == 0 then
            self.monitor.clear()
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "ME Drives", colors.white)
            local msg = #drives > 0 and "No drives with cells" or "No drives detected"
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, msg, colors.gray)
            return
        end

        -- Draw header
        self.monitor.clear()
        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(1, 1)
        self.monitor.write("ME Drives")
        self.monitor.setTextColor(colors.gray)
        local countStr = " (" .. #filteredDrives .. ")"
        self.monitor.write(countStr)

        -- Display drives in grid
        self.display:display(filteredDrives, function(drive)
            return module.formatDrive(drive)
        end)

        self.monitor.setTextColor(colors.white)
    end
}

return module
