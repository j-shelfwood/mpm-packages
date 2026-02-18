-- MachineGrid.lua
-- Grouped machine activity grid
-- Shows machine types as sections with colored status cells
-- Green = active/busy, Gray = idle/off

local BaseView = mpm('views/BaseView')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Text = mpm('utils/Text')
local Yield = mpm('utils/Yield')
local Activity = mpm('peripherals/MachineActivity')

local function clamp01(value)
    if type(value) ~= "number" then return nil end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function safeCall(p, method, ...)
    if not p or type(p[method]) ~= "function" then return nil end
    local ok, result = pcall(p[method], ...)
    if ok then return result end
    return nil
end

local function extractStackName(stack)
    if type(stack) ~= "table" then return nil end
    local name = stack.name or stack.registryName or stack.id
    if not name or name == "" then return nil end

    local count = stack.count or stack.amount or 0
    if type(count) == "number" and count <= 0 then
        return nil
    end

    return Text.prettifyName(name)
end

local function detectProgressState(peripheral)
    if not peripheral or type(peripheral.getRecipeProgress) ~= "function" then
        return false, nil, false
    end

    local bestProcess = nil
    local bestProgress = 0
    local indexedSupported = false

    for process = 0, 7 do
        local progress = safeCall(peripheral, "getRecipeProgress", process)
        if type(progress) == "number" then
            indexedSupported = true
            if progress > bestProgress then
                bestProgress = progress
                bestProcess = process
            end
        elseif process == 0 and not indexedSupported then
            break
        end
    end

    if indexedSupported then
        return bestProgress > 0, bestProcess, true
    end

    local progress = safeCall(peripheral, "getRecipeProgress")
    if type(progress) == "number" then
        return progress > 0, nil, false
    end

    return false, nil, false
end

local function getCraftingTarget(peripheral)
    if not peripheral then return nil end

    local isProgressActive, bestProcess, usesIndexedProgress = detectProgressState(peripheral)
    local outputName = nil

    -- Prefer process-specific factory slots when available.
    if usesIndexedProgress and bestProcess ~= nil then
        outputName = extractStackName(safeCall(peripheral, "getOutput", bestProcess))
            or extractStackName(safeCall(peripheral, "getInput", bestProcess))
    end

    -- Generic output/input APIs for many Mekanism machines/multiblocks.
    outputName = outputName
        or extractStackName(safeCall(peripheral, "getOutput"))
        or extractStackName(safeCall(peripheral, "getInput"))
        or extractStackName(safeCall(peripheral, "getOutputItem"))
        or extractStackName(safeCall(peripheral, "getInputItem"))
        or extractStackName(safeCall(peripheral, "getOutputItemOutput"))
        or extractStackName(safeCall(peripheral, "getInputItemInput"))

    -- Return target even when currently idle if a slot contains a stable item; caller can decide usage.
    return outputName, isProgressActive
end

local function getEnergyPercent(peripheral)
    local pct = clamp01(safeCall(peripheral, "getEnergyFilledPercentage"))
    if pct ~= nil then
        return pct
    end

    local energy = safeCall(peripheral, "getEnergy")
    local maxEnergy = safeCall(peripheral, "getMaxEnergy")
    if type(energy) == "number" and type(maxEnergy) == "number" and maxEnergy > 0 then
        return clamp01(energy / maxEnergy)
    end

    return nil
end

local function buildCraftingSummary(machines)
    local entries = {}
    for _, machine in ipairs(machines) do
        if machine.isActive and machine.crafting then
            table.insert(entries, machine.label .. ":" .. machine.crafting)
        end
    end

    if #entries == 0 then
        return nil
    end

    table.sort(entries)
    return table.concat(entries, ", ")
end

-- Draw a single machine cell as a 4-segment mini bar.
local function drawCell(monitor, x, y, machine)
    local isActive = machine and machine.isActive
    local energyPct = machine and machine.energyPct
    local segments = 4
    local filled = (energyPct and math.floor(energyPct * segments + 0.5)) or (isActive and segments or 0)
    if isActive and filled < 1 then
        filled = 1
    end
    if filled > segments then
        filled = segments
    end
    local fillColor = isActive and colors.lime or colors.lightGray
    local emptyColor = colors.gray

    for i = 1, segments do
        monitor.setBackgroundColor(i <= filled and fillColor or emptyColor)
        monitor.setCursorPos(x + i - 1, y)
        monitor.write(" ")
    end

    -- Idle machines without energy info stay dark.
    if not isActive and energyPct == nil then
        monitor.setBackgroundColor(colors.gray)
        monitor.setCursorPos(x, y)
        monitor.write("    ")
    end

    monitor.setCursorPos(x, y)
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
        self.craftingCache = {}
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
                entry.energyPct = getEnergyPercent(machine.peripheral)
                local detectedCraft, progressActive = getCraftingTarget(machine.peripheral)
                if progressActive then
                    entry.isActive = true
                end
                if detectedCraft then
                    self.craftingCache[entry.name] = detectedCraft
                end
                entry.crafting = detectedCraft or self.craftingCache[entry.name]
                if entry.isActive then activeCount = activeCount + 1 end
                table.insert(machines, entry)
                Yield.check(pollIdx, 6)
            end

            table.insert(sections, {
                label = typeData.label,
                color = typeData.classification.color or colors.white,
                active = activeCount,
                total = #machines,
                machines = machines,
                craftingSummary = buildCraftingSummary(machines)
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
                    entry.energyPct = getEnergyPercent(machine.peripheral)
                    local detectedCraft, progressActive = getCraftingTarget(machine.peripheral)
                    if progressActive then
                        entry.isActive = true
                    end
                    if detectedCraft then
                        self.craftingCache[entry.name] = detectedCraft
                    end
                    entry.crafting = detectedCraft or self.craftingCache[entry.name]
                    if entry.isActive then activeCount = activeCount + 1 end
                    table.insert(machines, entry)
                    Yield.check(pollIdx, 8)
                end

                table.insert(sections, {
                    label = typeData.label,
                    color = typeData.classification.color or colors.white,
                    active = activeCount,
                    total = #machines,
                    machines = machines,
                    craftingSummary = buildCraftingSummary(machines)
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
        -- Each section: header line + optional crafting line + ceil(machines/cellsPerRow) cell rows
        local cellWidth = 4   -- 4-char mini bar per machine
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

            if section.craftingSummary and currentY <= height then
                self.monitor.setTextColor(colors.lightGray)
                self.monitor.setCursorPos(1, currentY)
                self.monitor.write(Text.truncateMiddle("Now: " .. section.craftingSummary, width))
                currentY = currentY + 1
            end

            -- Draw machine cells in rows
            for idx, machine in ipairs(section.machines) do
                if currentY > height then break end

                local col = (idx - 1) % cellsPerRow
                local x = 1 + col * cellStep

                drawCell(self.monitor, x, currentY, machine)

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
