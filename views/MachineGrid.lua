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

-- Draw a larger machine card:
-- - Top row: compact power fill
-- - Middle: centered machine ID (#n)
-- - Bottom: current crafted/processed item when active
local function drawMachineCard(monitor, x, y, cardWidth, cardHeight, machine)
    local isActive = machine and machine.isActive
    local energyPct = machine and machine.energyPct

    local baseBg = isActive and colors.green or colors.gray
    for row = 0, cardHeight - 1 do
        monitor.setBackgroundColor(baseBg)
        monitor.setCursorPos(x, y + row)
        monitor.write(string.rep(" ", cardWidth))
    end

    local fill = 0
    if type(energyPct) == "number" then
        fill = math.floor(energyPct * cardWidth + 0.5)
    elseif isActive then
        fill = math.max(1, math.floor(cardWidth * 0.5))
    end
    if fill > 0 then
        monitor.setBackgroundColor(colors.lime)
        monitor.setCursorPos(x, y)
        monitor.write(string.rep(" ", math.min(cardWidth, fill)))
    end

    local idText = "#" .. tostring(machine.label or "?")
    local idX = x + math.max(0, math.floor((cardWidth - #idText) / 2))
    local idY = y + 1
    monitor.setBackgroundColor(baseBg)
    monitor.setTextColor(colors.black)
    monitor.setCursorPos(idX, idY)
    monitor.write(idText)

    local craftText = ""
    if isActive and machine.crafting then
        craftText = Text.truncateMiddle(machine.crafting, cardWidth)
    elseif isActive then
        craftText = "Active"
    else
        craftText = "Idle"
    end

    local craftX = x + math.max(0, math.floor((cardWidth - #craftText) / 2))
    local craftY = y + 2
    monitor.setCursorPos(craftX, craftY)
    monitor.write(craftText)

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
        local countStr = string.format("%d/%d active", data.totalActive, data.totalMachines)
        local titleMax = math.max(1, width - #countStr - 1)
        self.monitor.write(Text.truncateMiddle(title, titleMax))
        self.monitor.setTextColor(colors.lightGray)
        self.monitor.setCursorPos(math.max(1, width - #countStr + 1), 1)
        self.monitor.write(countStr)

        -- Render sections flowing top-to-bottom
        -- Each section: header line + rows of large machine cards
        local cardGap = 1
        local cardHeight = 4
        local cardWidth = 12
        local cardStep = cardWidth + cardGap
        local cardsPerRow = math.max(1, math.floor((width + cardGap) / cardStep))
        if cardsPerRow == 1 then
            cardWidth = width
            cardStep = cardWidth + cardGap
        end

        local currentY = 3  -- Start after title + blank line

        for _, section in ipairs(data.sections) do
            if currentY > height then break end

            -- Section header
            local label = Text.truncateMiddle(section.label, width)

            self.monitor.setTextColor(section.color or colors.white)
            self.monitor.setCursorPos(1, currentY)
            self.monitor.write(label)

            currentY = currentY + 1

            -- Draw machine cards in rows
            for idx, machine in ipairs(section.machines) do
                if currentY + cardHeight - 1 > height - 1 then break end

                local col = (idx - 1) % cardsPerRow
                local x = 1 + col * cardStep

                drawMachineCard(self.monitor, x, currentY, cardWidth, cardHeight, machine)

                -- Move to next row after filling this one
                if col == cardsPerRow - 1 or idx == #section.machines then
                    if idx < #section.machines then
                        currentY = currentY + cardHeight
                    end
                end
            end

            -- Advance past the last card row + gap
            currentY = currentY + cardHeight + 1
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
