-- MekDashboard.lua
-- Mekanism categorized overview dashboard
-- Shows all Mekanism categories (Processing, Generators, Multiblocks, Logistics)
-- with active/total counts per category and per-type breakdowns.
-- Designed for at-a-glance status on medium/large monitors.

local BaseView = mpm('views/BaseView')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Text = mpm('utils/Text')
local Activity = mpm('peripherals/MachineActivity')
local Yield = mpm('utils/Yield')

-- Ordered category display sequence (controls vertical order on screen)
local CATEGORY_ORDER = { "processing", "generators", "multiblocks", "logistics", "mi_machines", "other" }

local CATEGORY_LABELS = {
    processing  = "Processing",
    generators  = "Generators",
    multiblocks = "Multiblocks",
    logistics   = "Logistics",
    mi_machines = "Modern Industrialization",
    other       = "Other"
}

local CATEGORY_COLORS = {
    processing  = colors.cyan,
    generators  = colors.yellow,
    multiblocks = colors.purple,
    logistics   = colors.orange,
    mi_machines = colors.blue,
    other       = colors.lightGray
}

-- Build category summary rows from groupByCategoryRaw + live activity polling
local function buildCategoryData(modFilter)
    -- groupByCategoryRaw returns structure only; we poll activity here
    local groups = Activity.groupByCategoryRaw(modFilter)
    local categories = {}

    for catName, catData in pairs(groups) do
        local catActive = 0
        local catTotal = 0
        local typeRows = {}

        for pType, typeInfo in pairs(catData.types) do
            local typeActive = 0
            local typeTotal = #typeInfo.machines
            for idx, machine in ipairs(typeInfo.machines) do
                local isActive, _ = Activity.getActivity(machine.peripheral)
                if isActive then typeActive = typeActive + 1 end
                Yield.check(idx, 20)
            end
            catActive = catActive + typeActive
            catTotal  = catTotal + typeTotal
            table.insert(typeRows, {
                label  = typeInfo.shortName or pType,
                active = typeActive,
                total  = typeTotal
            })
        end

        -- Sort type rows: active-first, then alphabetical
        table.sort(typeRows, function(a, b)
            if a.active ~= b.active then return a.active > b.active end
            return a.label < b.label
        end)

        categories[catName] = {
            label    = catData.label or CATEGORY_LABELS[catName] or catName,
            color    = catData.color or CATEGORY_COLORS[catName] or colors.white,
            active   = catActive,
            total    = catTotal,
            typeRows = typeRows
        }
    end

    return categories
end

-- Render a horizontal activity bar (active/total ratio) in 1 char height
local function drawActivityBar(monitor, x, y, width, active, total)
    if width < 1 then return end
    local ratio = total > 0 and (active / total) or 0
    local filledW = math.max(0, math.min(width, math.floor(ratio * width + 0.5)))
    local emptyW  = width - filledW

    monitor.setCursorPos(x, y)
    if filledW > 0 then
        monitor.setBackgroundColor(colors.green)
        monitor.write(string.rep(" ", filledW))
    end
    if emptyW > 0 then
        monitor.setBackgroundColor(colors.gray)
        monitor.write(string.rep(" ", emptyW))
    end
    monitor.setBackgroundColor(colors.black)
end

return BaseView.custom({
    sleepTime = 3,
    listenEvents = {},

    configSchema = {
        {
            key     = "mod_filter",
            type    = "select",
            label   = "Mod Filter",
            options = Activity.getModFilters,
            default = "all"
        },
        {
            key     = "show_types",
            type    = "select",
            label   = "Show Type Rows",
            options = {
                { value = "yes", label = "Yes (expanded)" },
                { value = "no",  label = "No (summary only)" }
            },
            default = "yes"
        }
    },

    mount = function()
        -- Mount if any supported peripheral exists
        local names = peripheral.getNames()
        for _, name in ipairs(names) do
            local pType = peripheral.getType(name)
            if pType then
                local cls = Activity.classify(pType)
                if cls and cls.mod ~= "unknown" then
                    return true
                end
            end
        end
        return false
    end,

    init = function(self, config)
        self.modFilter  = config.mod_filter or "all"
        self.showTypes  = (config.show_types ~= "no")
    end,

    getData = function(self)
        local categories = buildCategoryData(self.modFilter)

        -- Build ordered list of present categories
        local ordered = {}
        for _, catName in ipairs(CATEGORY_ORDER) do
            if categories[catName] and categories[catName].total > 0 then
                table.insert(ordered, { name = catName, data = categories[catName] })
            end
        end
        -- Append any categories not in the predefined order
        for catName, catData in pairs(categories) do
            if catData.total > 0 then
                local found = false
                for _, co in ipairs(CATEGORY_ORDER) do
                    if co == catName then found = true; break end
                end
                if not found then
                    table.insert(ordered, { name = catName, data = catData })
                end
            end
        end

        local totalActive = 0
        local totalMachines = 0
        for _, entry in ipairs(ordered) do
            totalActive   = totalActive + entry.data.active
            totalMachines = totalMachines + entry.data.total
        end

        return {
            ordered       = ordered,
            totalActive   = totalActive,
            totalMachines = totalMachines
        }
    end,

    render = function(self, data)
        if not data or #data.ordered == 0 then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No Mekanism machines found", colors.orange)
            return
        end

        local w = self.width
        local h = self.height
        local y = 1

        -- Title bar
        local titleText  = "Mekanism Dashboard"
        local countStr   = string.format("%d/%d active", data.totalActive, data.totalMachines)
        local titleMax   = math.max(1, w - #countStr - 1)
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(1, y)
        self.monitor.write(Text.truncateMiddle(titleText, titleMax))
        self.monitor.setTextColor(colors.lightGray)
        self.monitor.setCursorPos(w - #countStr + 1, y)
        self.monitor.write(countStr)
        y = y + 1

        -- Separator
        if y <= h then
            self.monitor.setBackgroundColor(colors.black)
            self.monitor.setTextColor(colors.gray)
            self.monitor.setCursorPos(1, y)
            self.monitor.write(string.rep("-", w))
            y = y + 1
        end

        -- Category sections
        for _, entry in ipairs(data.ordered) do
            if y > h then break end

            local cat    = entry.data
            local catColor = cat.color or colors.white

            -- Category header: "[COLOR] Label          ##/## [bar]"
            local barWidth   = math.max(0, math.floor(w * 0.18))
            local countPart  = string.format(" %d/%d", cat.active, cat.total)
            local labelMax   = math.max(1, w - #countPart - barWidth - 1)
            local labelText  = Text.truncateMiddle(cat.label, labelMax)

            self.monitor.setBackgroundColor(colors.black)
            self.monitor.setTextColor(catColor)
            self.monitor.setCursorPos(1, y)
            self.monitor.write(labelText)

            self.monitor.setTextColor(cat.active > 0 and colors.lime or colors.gray)
            self.monitor.setCursorPos(1 + #labelText, y)
            self.monitor.write(countPart)

            -- Mini activity bar at right edge
            local barX = w - barWidth + 1
            if barWidth >= 3 and barX >= 1 + #labelText + #countPart + 1 then
                drawActivityBar(self.monitor, barX, y, barWidth, cat.active, cat.total)
            end

            y = y + 1

            -- Per-type rows (indented)
            if self.showTypes then
                for _, row in ipairs(cat.typeRows) do
                    if y > h - 1 then break end

                    -- "  TypeName       a/t"
                    local rowCount   = string.format("%d/%d", row.active, row.total)
                    local indent     = 2
                    local labelW     = math.max(1, w - indent - #rowCount - 1)
                    local rowLabel   = Text.truncateMiddle(row.label, labelW)

                    self.monitor.setBackgroundColor(colors.black)
                    self.monitor.setTextColor(colors.lightGray)
                    self.monitor.setCursorPos(1, y)
                    self.monitor.write(string.rep(" ", indent))
                    self.monitor.write(rowLabel)

                    -- Pad to align count column
                    local used = indent + #rowLabel
                    local gap  = w - used - #rowCount
                    if gap > 0 then
                        self.monitor.write(string.rep(" ", gap))
                    end

                    local countColor = row.active > 0 and colors.lime or colors.gray
                    self.monitor.setTextColor(countColor)
                    self.monitor.write(rowCount)

                    y = y + 1
                end
            end

            -- Gap between categories (skip last)
            if y <= h then
                y = y + 1
            end
        end

        -- Bottom status bar: full-width activity ratio
        if h >= 3 then
            local ratio      = data.totalMachines > 0 and (data.totalActive / data.totalMachines) or 0
            local filledW    = math.floor(w * ratio)
            local emptyW     = w - filledW

            self.monitor.setCursorPos(1, h)
            if filledW > 0 then
                self.monitor.setBackgroundColor(colors.green)
                self.monitor.write(string.rep(" ", filledW))
            end
            if emptyW > 0 then
                self.monitor.setBackgroundColor(colors.gray)
                self.monitor.write(string.rep(" ", emptyW))
            end

            local statusText = string.format(" %d/%d active ", data.totalActive, data.totalMachines)
            local textX      = math.max(1, math.floor((w - #statusText) / 2) + 1)
            self.monitor.setCursorPos(textX, h)
            self.monitor.setBackgroundColor(ratio > 0.5 and colors.green or colors.gray)
            self.monitor.setTextColor(colors.black)
            self.monitor.write(statusText)
            self.monitor.setBackgroundColor(colors.black)
        end

        self.monitor.setTextColor(colors.white)
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Mekanism Dashboard", colors.cyan)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "No Mekanism machines found", colors.gray)
    end
})
