-- MachineActivity.lua
-- Unified machine activity display for MI, Mekanism, and other mods
-- Shows categorized grid of machines with activity status
-- Green = active/busy, Gray = idle/off

local BaseView = mpm('views/BaseView')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')
local Activity = mpm('peripherals/MachineActivity')

-- Display modes
local MODE_ALL = "all"
local MODE_TYPE = "type"

-- Adaptive cell size based on monitor dimensions
local function getCellSize(width, height)
    local area = width * height
    if area >= 600 then return 3  -- Large monitor (e.g., 4x3 at 0.5 scale)
    elseif area >= 200 then return 2  -- Medium monitor
    else return 2 end  -- Small monitor, keep minimum 2
end

-- Draw a single machine cell (colored square with label)
local function drawCell(monitor, x, y, size, isActive, label)
    local bgColor = isActive and colors.green or colors.gray
    monitor.setBackgroundColor(bgColor)

    for i = 0, size - 1 do
        monitor.setCursorPos(x, y + i)
        monitor.write(string.rep(" ", size))
    end

    if label and size >= 2 then
        monitor.setTextColor(isActive and colors.black or colors.lightGray)
        local displayLabel = label:sub(1, size)
        local labelX = x + math.max(0, math.floor((size - #displayLabel) / 2))
        local labelY = y + math.floor((size - 1) / 2)
        monitor.setCursorPos(labelX, labelY)
        monitor.write(displayLabel)
    end
end

-- Draw an activity ratio bar at the bottom
local function drawStatusBar(monitor, y, width, active, total)
    local ratio = total > 0 and (active / total) or 0
    local filledWidth = math.floor(width * ratio)
    local emptyWidth = width - filledWidth

    monitor.setCursorPos(1, y)

    if filledWidth > 0 then
        monitor.setBackgroundColor(colors.green)
        monitor.write(string.rep(" ", filledWidth))
    end

    if emptyWidth > 0 then
        monitor.setBackgroundColor(colors.gray)
        monitor.write(string.rep(" ", emptyWidth))
    end

    -- Overlay text
    local statusText = string.format(" %d/%d active ", active, total)
    local textX = math.max(1, math.floor((width - #statusText) / 2) + 1)
    monitor.setCursorPos(textX, y)
    monitor.setBackgroundColor(ratio > 0.5 and colors.green or colors.gray)
    monitor.setTextColor(colors.black)
    monitor.write(statusText)

    monitor.setBackgroundColor(colors.black)
end

local function renderSingleType(self, data)
    local machines = data.machines

    if #machines == 0 then
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No machines found", colors.orange)
        return
    end

    -- Title
    local title = data.typeName or "Machines"
    local titleColor = data.classification and data.classification.color or colors.white
    MonitorHelpers.writeCentered(self.monitor, 1, title, titleColor)

    -- Adaptive cell size
    local cellSize = getCellSize(self.width, self.height)
    local cellGap = 1
    local cellStep = cellSize + cellGap
    local cols = math.max(1, math.floor((self.width + cellGap) / cellStep))

    local startY = 3
    local activeCount = 0

    for idx, machine in ipairs(machines) do
        local col = (idx - 1) % cols
        local row = math.floor((idx - 1) / cols)
        local x = col * cellStep + 1
        local y = startY + row * cellStep

        -- Stop if we'd render past the status bar
        if y + cellSize > self.height then break end

        drawCell(self.monitor, x, y, cellSize, machine.isActive, machine.label)
        if machine.isActive then activeCount = activeCount + 1 end
    end

    -- Status bar
    drawStatusBar(self.monitor, self.height, self.width, activeCount, #machines)
    self.monitor.setTextColor(colors.white)
end

local function renderCategorized(self, data)
    local sections = data.sections

    if not sections or #sections == 0 then
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No machines found", colors.orange)
        return
    end

    -- Title row
    local filterLabel = self.modFilter == "all" and "Machines" or
                       (self.modFilter == "mekanism" and "Mekanism" or "MI")
    self.monitor.setBackgroundColor(colors.black)
    self.monitor.setTextColor(colors.white)
    self.monitor.setCursorPos(1, 1)
    self.monitor.write(filterLabel)

    -- Active count on right side of title
    local countStr = string.format("%d/%d", data.totalActive, data.totalMachines)
    self.monitor.setTextColor(data.totalActive > 0 and colors.lime or colors.gray)
    self.monitor.setCursorPos(math.max(1, self.width - #countStr + 1), 1)
    self.monitor.write(countStr)

    -- Adaptive cell size
    local cellSize = getCellSize(self.width, self.height)
    local cellGap = 1
    local cellStep = cellSize + cellGap

    -- Render sections
    local y = 3
    local overflow = false

    for _, section in ipairs(sections) do
        if overflow then break end

        -- Category header
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(section.color or colors.white)
        self.monitor.setCursorPos(1, y)
        local headerText = string.format("%s (%d/%d)", section.label, section.active, section.total)
        self.monitor.write(headerText:sub(1, self.width))
        y = y + 1

        -- Types within category
        for _, typeEntry in ipairs(section.types) do
            if overflow then break end

            -- Type label row (if more than one type in category or enough space)
            if #section.types > 1 and y < self.height then
                self.monitor.setBackgroundColor(colors.black)
                self.monitor.setTextColor(colors.lightGray)
                self.monitor.setCursorPos(2, y)
                local typeLabel = string.format("%s %d/%d", typeEntry.shortName, typeEntry.active, typeEntry.total)
                self.monitor.write(typeLabel:sub(1, self.width - 2))
                y = y + 1
            end

            -- Machine cells for this type
            local x = 1
            for _, machine in ipairs(typeEntry.machines) do
                -- Wrap to next row if needed
                if x + cellSize - 1 > self.width then
                    x = 1
                    y = y + cellStep
                end

                -- Stop rendering if we'd overlap status bar
                if y + cellSize > self.height then
                    overflow = true
                    break
                end

                drawCell(self.monitor, x, y, cellSize, machine.isActive, machine.label)
                x = x + cellStep
            end

            -- Move to next line after cells
            if not overflow and x > 1 then
                y = y + cellStep
            end
        end

        -- Gap between categories
        if not overflow then
            y = y + 1
        end
    end

    -- Status bar at bottom
    drawStatusBar(self.monitor, self.height, self.width, data.totalActive, data.totalMachines)
    self.monitor.setTextColor(colors.white)
end

return BaseView.custom({
    sleepTime = 1,

    configSchema = {
        {
            key = "mod_filter",
            type = "select",
            label = "Mod Filter",
            options = Activity.getModFilters,
            default = "all"
        },
        {
            key = "display_mode",
            type = "select",
            label = "Display Mode",
            options = function()
                return {
                    { value = MODE_ALL, label = "All (Categorized)" },
                    { value = MODE_TYPE, label = "Single Type" }
                }
            end,
            default = MODE_ALL
        },
        {
            key = "machine_type",
            type = "select",
            label = "Machine Type",
            options = function(config)
                return Activity.getMachineTypes((config and config.mod_filter) or "all")
            end,
            dependsOn = "mod_filter",
            showWhen = function(config)
                return config.display_mode == MODE_TYPE
            end
        }
    },

    mount = function()
        local discovered = Activity.discoverAll()
        return next(discovered) ~= nil
    end,

    init = function(self, config)
        self.modFilter = config.mod_filter or "all"
        self.displayMode = config.display_mode or MODE_ALL
        self.machineType = config.machine_type
    end,

    getData = function(self)
        if self.displayMode == MODE_TYPE and self.machineType then
            -- Single type: discover and poll activity in one pass
            local discovered = Activity.discoverAll()
            local typeData = discovered[self.machineType]

            if not typeData then
                return { mode = MODE_TYPE, machines = {}, typeName = self.machineType }
            end

            local machines = {}
            for idx, machine in ipairs(typeData.machines) do
                local isActive, activityData = Activity.getActivity(machine.peripheral)
                table.insert(machines, {
                    label = machine.name:match("_(%d+)$") or tostring(idx),
                    isActive = isActive,
                    data = activityData
                })
                Yield.check(idx, 5)
            end

            return {
                mode = MODE_TYPE,
                machines = machines,
                typeName = Activity.getShortName(self.machineType),
                classification = typeData.classification
            }
        else
            -- All mode: use raw grouping (no activity polling), then poll once
            local groups = Activity.groupByCategoryRaw(self.modFilter)

            local sections = {}
            local totalActive = 0
            local totalMachines = 0
            local pollIdx = 0

            -- Sort categories for consistent display
            local sortedCatNames = {}
            for catName in pairs(groups) do
                table.insert(sortedCatNames, catName)
            end
            table.sort(sortedCatNames, function(a, b)
                return (groups[a].label or a) < (groups[b].label or b)
            end)

            for _, catName in ipairs(sortedCatNames) do
                local catData = groups[catName]

                -- Sort types within category
                local sortedTypeNames = {}
                for pType in pairs(catData.types) do
                    table.insert(sortedTypeNames, pType)
                end
                table.sort(sortedTypeNames, function(a, b)
                    return (catData.types[a].shortName or a) < (catData.types[b].shortName or b)
                end)

                local catActive = 0
                local catTotal = 0
                local typeEntries = {}

                for _, pType in ipairs(sortedTypeNames) do
                    local typeInfo = catData.types[pType]
                    local machines = {}
                    local typeActive = 0

                    for _, machine in ipairs(typeInfo.machines) do
                        pollIdx = pollIdx + 1
                        local isActive, activityData = Activity.getActivity(machine.peripheral)
                        if isActive then
                            typeActive = typeActive + 1
                        end
                        table.insert(machines, {
                            label = machine.name:match("_(%d+)$") or "?",
                            isActive = isActive,
                            data = activityData
                        })
                        Yield.check(pollIdx, 8)
                    end

                    catActive = catActive + typeActive
                    catTotal = catTotal + #machines

                    table.insert(typeEntries, {
                        shortName = typeInfo.shortName,
                        machines = machines,
                        active = typeActive,
                        total = #machines
                    })
                end

                totalActive = totalActive + catActive
                totalMachines = totalMachines + catTotal

                table.insert(sections, {
                    label = catData.label,
                    color = catData.color,
                    types = typeEntries,
                    active = catActive,
                    total = catTotal
                })
            end

            return {
                mode = MODE_ALL,
                sections = sections,
                totalActive = totalActive,
                totalMachines = totalMachines
            }
        end
    end,

    render = function(self, data)
        if data.mode == MODE_TYPE then
            renderSingleType(self, data)
        else
            renderCategorized(self, data)
        end
    end,
    renderSingleType = renderSingleType,
    renderCategorized = renderCategorized,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Machine Activity", colors.white)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "No compatible machines found", colors.gray)
    end
})
