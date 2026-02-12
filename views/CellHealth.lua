-- CellHealth.lua
-- Displays storage cell status and health monitoring
-- Shows usage percentages, warns on nearly-full cells

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

-- Parse cell size from bytes (1k, 4k, 16k, 64k, 256k)
local function getCellSize(bytes)
    if not bytes then return "?" end
    local kb = bytes / 1024
    if kb >= 1024 then
        return string.format("%.0fM", kb / 1024)
    else
        return string.format("%.0fk", kb)
    end
end

-- Parse cell type (ITEM, FLUID, etc.)
local function getCellType(typeStr)
    if not typeStr then return "?" end
    -- type is like "appeng.api.stacks.AEItemKey" - extract last part
    local parts = {}
    for part in string.gmatch(typeStr, "[^.]+") do
        table.insert(parts, part)
    end
    local lastPart = parts[#parts] or typeStr
    -- "AEItemKey" -> "ITEM"
    return lastPart:gsub("AE", ""):gsub("Key", ""):upper()
end

return BaseView.custom({
    sleepTime = 5,

    configSchema = {
        {
            key = "warningPercent",
            type = "number",
            label = "Warning Above %",
            default = 90,
            min = 50,
            max = 99,
            presets = {75, 85, 90, 95}
        },
        {
            key = "sortBy",
            type = "select",
            label = "Sort By",
            options = {
                { value = "usage", label = "Usage %" },
                { value = "size", label = "Size" },
                { value = "type", label = "Type" }
            },
            default = "usage"
        }
    },

    mount = function()
        return AEInterface.exists()
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil
        self.warningPercent = config.warningPercent or 90
        self.sortBy = config.sortBy or "usage"
    end,

    getData = function(self)
        -- Get cell data
        local cells = self.interface:getCells()
        if not cells then return {} end

        Yield.yield()

        -- Parse and calculate cell info
        local cellData = {}
        for _, cell in ipairs(cells) do
            local bytes = cell.bytes or 0
            local usedBytes = cell.usedBytes or 0
            local percentage = bytes > 0 and (usedBytes / bytes * 100) or 0

            table.insert(cellData, {
                size = getCellSize(bytes),
                type = getCellType(cell.type),
                bytes = bytes,
                usedBytes = usedBytes,
                percentage = percentage,
                totalTypes = cell.totalTypes or 0
            })
        end

        -- Sort cells
        if self.sortBy == "usage" then
            table.sort(cellData, function(a, b) return a.percentage > b.percentage end)
        elseif self.sortBy == "size" then
            table.sort(cellData, function(a, b) return a.bytes > b.bytes end)
        elseif self.sortBy == "type" then
            table.sort(cellData, function(a, b)
                if a.type == b.type then
                    return a.percentage > b.percentage
                end
                return a.type < b.type
            end)
        end

        return cellData
    end,

    render = function(self, data)
        -- Row 1: Title
        local title = "Storage Cells (" .. #data .. ")"
        MonitorHelpers.writeCentered(self.monitor, 1, title, colors.white)

        -- No cells case
        if #data == 0 then
            self.monitor.setTextColor(colors.gray)
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No cells found", colors.gray)
            return
        end

        -- Calculate summary
        local totalCells = #data
        local totalUsage = 0
        local warningCount = 0
        local totalTypes = 0
        for _, cell in ipairs(data) do
            totalUsage = totalUsage + cell.percentage
            if cell.percentage >= self.warningPercent then
                warningCount = warningCount + 1
            end
            totalTypes = totalTypes + (cell.totalTypes or 0)
        end
        local avgUsage = totalCells > 0 and (totalUsage / totalCells) or 0

        -- Row 3: Summary stats
        local summaryY = 3
        if self.height >= 6 then
            self.monitor.setTextColor(colors.lightGray)
            self.monitor.setCursorPos(1, summaryY)
            self.monitor.write(string.format("Avg: %.1f%%", avgUsage))

            if warningCount > 0 then
                self.monitor.setTextColor(colors.red)
                local warnStr = string.format("  %d >%d%%", warningCount, self.warningPercent)
                local warnX = self.width - #warnStr + 1
                self.monitor.setCursorPos(warnX, summaryY)
                self.monitor.write(warnStr)
            else
                self.monitor.setTextColor(colors.gray)
                local typesStr = "Types: " .. totalTypes
                local typesX = self.width - #typesStr + 1
                self.monitor.setCursorPos(typesX, summaryY)
                self.monitor.write(typesStr)
            end
        end

        -- Row 5+: Cell list
        local startY = 5
        local maxRows = self.height - startY + 1

        for i, cell in ipairs(data) do
            if i > maxRows then break end

            local y = startY + i - 1

            -- Determine color
            local barColor = colors.green
            if cell.percentage > self.warningPercent then
                barColor = colors.red
            elseif cell.percentage > 75 then
                barColor = colors.orange
            elseif cell.percentage > 50 then
                barColor = colors.yellow
            end

            -- Format: "4k ITEM [====     ] 45.2%"
            local label = string.format("%s %s", cell.size, cell.type)
            label = Text.truncateMiddle(label, 10)  -- Limit label width

            self.monitor.setTextColor(colors.white)
            self.monitor.setCursorPos(1, y)
            self.monitor.write(label)

            -- Progress bar (remaining width minus percentage display)
            local pctStr = string.format("%.1f%%", cell.percentage)
            local barWidth = self.width - #label - #pctStr - 2  -- 2 for spacing

            if barWidth >= 5 then
                MonitorHelpers.drawProgressBar(
                    self.monitor,
                    #label + 2,
                    y,
                    barWidth,
                    cell.percentage,
                    barColor,
                    colors.gray,
                    true
                )
            end

            -- Percentage on right
            self.monitor.setTextColor(barColor)
            self.monitor.setCursorPos(self.width - #pctStr + 1, y)
            self.monitor.write(pctStr)
        end

        self.monitor.setTextColor(colors.white)
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, 1, "Storage Cells (0)", colors.white)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No cells found", colors.gray)
    end,

    errorMessage = "Error reading cells"
})
