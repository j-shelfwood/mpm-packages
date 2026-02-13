-- DriveStatus.lua
-- Displays grid overview of all AE2 ME Drives
-- Shows drive status, cell count, and storage usage

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')

return BaseView.grid({
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

    mount = function()
        local exists, pType = AEInterface.exists()
        return exists and pType == "me_bridge"
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil
        self.showEmpty = config.showEmpty ~= false
    end,

    getData = function(self)
        -- Check interface is available
        if not self.interface then return nil end

        -- Get all drives
        local drives = self.interface:getDrives()
        if not drives then return {} end

        -- Filter empty drives if configured
        local filteredDrives = {}
        for _, drive in ipairs(drives) do
            local cells = drive.cells or {}
            local hasCells = #cells > 0
            if self.showEmpty or hasCells then
                table.insert(filteredDrives, drive)
            end
        end

        return filteredDrives
    end,

    header = function(self, data)
        return {
            text = "ME Drives",
            color = colors.white,
            secondary = " (" .. #data .. ")",
            secondaryColor = colors.gray
        }
    end,

    formatItem = function(self, driveData)
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
            local totalStr = Text.formatNumber(totalBytes, 1) .. "B"
            table.insert(lines, usedStr .. "/" .. totalStr)
            table.insert(lineColors, colors.gray)
        end

        return {
            lines = lines,
            colors = lineColors,
            aligns = { "left", "left", "right" }
        }
    end,

    emptyMessage = "No drives detected",
    maxItems = 50
})
