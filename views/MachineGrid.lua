-- MachineGrid.lua
-- Compact activity grid for machines across mods
-- Green = active/busy, Gray = idle/off

local BaseView = mpm('views/BaseView')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')
local Activity = mpm('peripherals/MachineActivity')

-- Draw a single machine cell (colored square with optional label)
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

    local statusText = string.format(" %d/%d active ", active, total)
    local textX = math.max(1, math.floor((width - #statusText) / 2) + 1)
    monitor.setCursorPos(textX, y)
    monitor.setBackgroundColor(ratio > 0.5 and colors.green or colors.gray)
    monitor.setTextColor(colors.black)
    monitor.write(statusText)

    monitor.setBackgroundColor(colors.black)
end

-- Compute best cell size for available space
local function computeGrid(width, height, count)
    local reservedRows = 2  -- header + status bar
    local availableHeight = math.max(1, height - reservedRows)

    for size = 4, 1, -1 do
        local gap = size == 1 and 0 or 1
        local step = size + gap
        local cols = math.max(1, math.floor((width + gap) / step))
        local rows = math.max(1, math.floor((availableHeight + gap) / step))
        if cols * rows >= count then
            return size, gap, cols, rows
        end
    end

    return 1, 0, width, availableHeight
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
            key = "machine_type",
            type = "select",
            label = "Machine Type",
            options = function(config)
                return Activity.getMachineTypes((config and config.mod_filter) or "all")
            end
        }
    },

    mount = function()
        local discovered = Activity.discoverAll()
        return next(discovered) ~= nil
    end,

    init = function(self, config)
        self.modFilter = config.mod_filter or "all"
        self.machineType = config.machine_type
    end,

    getData = function(self)
        local discovered = Activity.discover(self.modFilter)
        local machines = {}
        local title = self.modFilter == "all" and "Machines" or
                     (self.modFilter == "mekanism" and "Mekanism" or "MI")
        local titleColor = colors.white
        local totalActive = 0
        local pollIdx = 0

        if self.machineType then
            local typeData = discovered[self.machineType]
            if not typeData then
                return { machines = {}, title = title, titleColor = colors.gray, totalActive = 0, totalMachines = 0 }
            end

            title = Activity.getShortName(self.machineType)
            if typeData.classification.mod == "mi" then
                title = "MI: " .. title
            end
            titleColor = typeData.classification.color or colors.white

            for idx, machine in ipairs(typeData.machines) do
                local isActive, activityData = Activity.getActivity(machine.peripheral)
                if isActive then totalActive = totalActive + 1 end
                table.insert(machines, {
                    label = machine.name:match("_(%d+)$") or tostring(idx),
                    isActive = isActive,
                    data = activityData
                })
                Yield.check(idx, 6)
            end
        else
            for _, typeData in pairs(discovered) do
                for _, machine in ipairs(typeData.machines) do
                    pollIdx = pollIdx + 1
                    local isActive, activityData = Activity.getActivity(machine.peripheral)
                    if isActive then totalActive = totalActive + 1 end
                    table.insert(machines, {
                        label = machine.name:match("_(%d+)$") or "?",
                        isActive = isActive,
                        data = activityData
                    })
                    Yield.check(pollIdx, 8)
                end
            end
        end

        return {
            machines = machines,
            title = title,
            titleColor = titleColor,
            totalActive = totalActive,
            totalMachines = #machines
        }
    end,

    render = function(self, data)
        if not data or #data.machines == 0 then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No machines found", colors.orange)
            return
        end

        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(data.titleColor or colors.white)
        self.monitor.setCursorPos(1, 1)
        self.monitor.write(data.title)

        local countStr = string.format("%d/%d", data.totalActive, data.totalMachines)
        self.monitor.setTextColor(data.totalActive > 0 and colors.lime or colors.gray)
        self.monitor.setCursorPos(math.max(1, self.width - #countStr + 1), 1)
        self.monitor.write(countStr)

        local cellSize, cellGap, cols = computeGrid(self.width, self.height, #data.machines)
        local cellStep = cellSize + cellGap
        local startY = 2

        for idx, machine in ipairs(data.machines) do
            local col = (idx - 1) % cols
            local row = math.floor((idx - 1) / cols)
            local x = col * cellStep + 1
            local y = startY + row * cellStep

            if y + cellSize > self.height then break end

            drawCell(self.monitor, x, y, cellSize, machine.isActive, machine.label)
        end

        drawStatusBar(self.monitor, self.height, self.width, data.totalActive, data.totalMachines)
        self.monitor.setTextColor(colors.white)
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Machine Grid", colors.white)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "No compatible machines found", colors.gray)
    end
})
