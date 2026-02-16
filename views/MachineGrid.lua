-- MachineGrid.lua
-- Grouped machine activity grid
-- Shows machine types as sections with colored status cells
-- Green = active/busy, Gray = idle/off

local BaseView = mpm('views/BaseView')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Text = mpm('utils/Text')
local Yield = mpm('utils/Yield')
local Activity = mpm('peripherals/MachineActivity')

-- Draw a single machine cell (colored square)
local function drawCell(monitor, x, y, isActive)
    local bgColor = isActive and colors.green or colors.gray
    monitor.setBackgroundColor(bgColor)
    monitor.setCursorPos(x, y)
    monitor.write("  ")  -- 2-char wide cell
    monitor.setBackgroundColor(colors.black)
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
                return Activity.getMachineTypeOptions((config and config.mod_filter) or "all")
            end
        }
    },

    mount = function()
        local discovered = Activity.discoverAll()
        return next(discovered) ~= nil
    end,

    init = function(self, config)
        self.modFilter = config.mod_filter or "all"
        self.machineType = Activity.normalizeMachineType(config.machine_type)
    end,

    getData = function(self)
        local types = Activity.buildTypeList(self.modFilter)
        local sections = {}
        local totalActive = 0
        local totalMachines = 0
        local pollIdx = 0

        if self.machineType then
            -- Single type mode
            local typeData = nil
            for _, info in ipairs(types) do
                if info.type == self.machineType then
                    typeData = info
                    break
                end
            end
            if not typeData then
                return { sections = {}, totalActive = 0, totalMachines = 0 }
            end

            local machines = {}
            local activeCount = 0
            for idx, machine in ipairs(typeData.machines) do
                pollIdx = pollIdx + 1
                local entry = Activity.buildMachineEntry(machine, idx, typeData.type)
                if entry.isActive then activeCount = activeCount + 1 end
                table.insert(machines, entry)
                Yield.check(pollIdx, 6)
            end

            table.insert(sections, {
                label = typeData.label,
                color = typeData.classification.color or colors.white,
                active = activeCount,
                total = #machines,
                machines = machines
            })
            totalActive = activeCount
            totalMachines = #machines
        else
            -- All types mode: one section per type
            for _, typeData in ipairs(types) do
                local machines = {}
                local activeCount = 0
                for idx, machine in ipairs(typeData.machines) do
                    pollIdx = pollIdx + 1
                    local entry = Activity.buildMachineEntry(machine, idx, typeData.type)
                    if entry.isActive then activeCount = activeCount + 1 end
                    table.insert(machines, entry)
                    Yield.check(pollIdx, 8)
                end

                table.insert(sections, {
                    label = typeData.label,
                    color = typeData.classification.color or colors.white,
                    active = activeCount,
                    total = #machines,
                    machines = machines
                })
                totalActive = totalActive + activeCount
                totalMachines = totalMachines + #machines
            end
        end

        return {
            sections = sections,
            totalActive = totalActive,
            totalMachines = totalMachines
        }
    end,

    render = function(self, data)
        if not data or not data.sections or #data.sections == 0 then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No machines found", colors.orange)
            return
        end

        local width = self.width
        local height = self.height

        -- Title bar: "Machines" + "active/total"
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(1, 1)

        local title = self.machineType and data.sections[1].label or "Machines"
        self.monitor.write(Text.truncateMiddle(title, width - 8))

        local countStr = string.format("%d/%d", data.totalActive, data.totalMachines)
        self.monitor.setTextColor(data.totalActive > 0 and colors.lime or colors.gray)
        self.monitor.setCursorPos(math.max(1, width - #countStr + 1), 1)
        self.monitor.write(countStr)

        -- Render sections flowing top-to-bottom
        -- Each section: 1 header line + ceil(machines/cellsPerRow) cell rows
        local cellWidth = 2   -- 2 chars per cell
        local cellGap = 1     -- 1 char gap between cells
        local cellStep = cellWidth + cellGap
        local cellsPerRow = math.max(1, math.floor((width + cellGap) / cellStep))

        local currentY = 3  -- Start after title + blank line

        for _, section in ipairs(data.sections) do
            if currentY > height then break end

            -- Section header: "Type Name       3/5"
            local countText = string.format("%d/%d", section.active, section.total)
            local labelWidth = width - #countText - 1
            local label = Text.truncateMiddle(section.label, math.max(1, labelWidth))

            self.monitor.setTextColor(section.color or colors.white)
            self.monitor.setCursorPos(1, currentY)
            self.monitor.write(label)

            self.monitor.setTextColor(section.active > 0 and colors.lime or colors.gray)
            self.monitor.setCursorPos(math.max(1, width - #countText + 1), currentY)
            self.monitor.write(countText)

            currentY = currentY + 1

            -- Draw machine cells in rows
            for idx, machine in ipairs(section.machines) do
                if currentY > height then break end

                local col = (idx - 1) % cellsPerRow
                local x = 1 + col * cellStep

                drawCell(self.monitor, x, currentY, machine.isActive)

                -- Move to next row after filling this one
                if col == cellsPerRow - 1 or idx == #section.machines then
                    if idx < #section.machines then
                        currentY = currentY + 1
                    end
                end
            end

            -- Advance past the last cell row + gap
            currentY = currentY + 2  -- 1 for current row + 1 gap
        end

        -- Status bar at bottom
        if height >= 3 then
            local ratio = data.totalMachines > 0 and (data.totalActive / data.totalMachines) or 0
            local filledWidth = math.floor(width * ratio)
            local emptyWidth = width - filledWidth

            self.monitor.setCursorPos(1, height)
            if filledWidth > 0 then
                self.monitor.setBackgroundColor(colors.green)
                self.monitor.write(string.rep(" ", filledWidth))
            end
            if emptyWidth > 0 then
                self.monitor.setBackgroundColor(colors.gray)
                self.monitor.write(string.rep(" ", emptyWidth))
            end

            local statusText = string.format(" %d/%d active ", data.totalActive, data.totalMachines)
            local textX = math.max(1, math.floor((width - #statusText) / 2) + 1)
            self.monitor.setCursorPos(textX, height)
            self.monitor.setBackgroundColor(ratio > 0.5 and colors.green or colors.gray)
            self.monitor.setTextColor(colors.black)
            self.monitor.write(statusText)
            self.monitor.setBackgroundColor(colors.black)
        end

        self.monitor.setTextColor(colors.white)
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Machine Grid", colors.white)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "No compatible machines found", colors.gray)
    end
})
