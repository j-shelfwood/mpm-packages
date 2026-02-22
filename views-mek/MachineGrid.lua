-- MachineGrid.lua
-- Grouped machine activity grid
-- Shows machine types as sections with colored status cells
-- Green = active/busy, Gray = idle/off

local BaseView = mpm('views/BaseView')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Text = mpm('utils/Text')
local Activity = mpm('peripherals/MachineActivity')
local Yield = mpm('utils/Yield')

local listenEvents = {}

_G._shelfos_machineGridShared = _G._shelfos_machineGridShared or {
    byFilter = {}
}

local function getSharedFilterState(modFilter)
    local store = _G._shelfos_machineGridShared
    local key = modFilter or "all"
    local state = store.byFilter[key]
    if not state then
        state = {
            types = {},
            typeByName = {},
            machineEntries = {},
            machineSeen = {},
            dueEntries = {},
            lastTypesAt = 0,
            lastSweepAt = 0,
            pollCursor = 0,
            refreshingTypes = false,
            sweeping = false
        }
        store.byFilter[key] = state
    end
    return state
end

local function clamp01(value)
    if type(value) ~= "number" then return nil end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function resolveTextColor(value, fallback)
    if type(value) == "number" then
        return value
    end

    if type(value) == "table" then
        if type(value.color) == "number" then
            return value.color
        end
        if type(value[1]) == "number" then
            return value[1]
        end
    end

    return fallback or colors.white
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

local function readCraftName(peripheral, methodName, process)
    if process ~= nil then
        return extractStackName(safeCall(peripheral, methodName, process))
    end
    return extractStackName(safeCall(peripheral, methodName))
end

local function getCraftingTarget(peripheral, entry, isActive)
    if not peripheral then return nil end

    if entry and entry.craftMethod then
        local process = entry.craftUsesIndexed and 0 or nil
        local knownName = readCraftName(peripheral, entry.craftMethod, process)
        if knownName then
            return knownName
        end
        entry.craftMethod = nil
        entry.craftUsesIndexed = false
    end

    if entry and entry.noCraftSignals and not isActive then
        return nil
    end

    local candidates = {
        { method = "getOutput", indexed = true },
        { method = "getInput", indexed = true },
        { method = "getOutput", indexed = false },
        { method = "getInput", indexed = false },
        { method = "getOutputItem", indexed = false },
        { method = "getInputItem", indexed = false },
        { method = "getOutputItemOutput", indexed = false },
        { method = "getInputItemInput", indexed = false }
    }

    for _, candidate in ipairs(candidates) do
        local process = candidate.indexed and 0 or nil
        local outputName = readCraftName(peripheral, candidate.method, process)
        if outputName then
            if entry then
                entry.craftMethod = candidate.method
                entry.craftUsesIndexed = candidate.indexed
                entry.noCraftSignals = false
            end
            return outputName
        end
    end

    if entry then
        entry.noCraftSignals = true
    end

    return nil
end

local function getEnergyPercent(peripheral)
    local pct = Activity.getEnergyPercent(peripheral)
    if pct == nil then
        return nil
    end
    return clamp01(pct)
end

local function readActivityState(peripheral)
    if not peripheral then
        return nil, false
    end

    if Activity.supportsActivity(peripheral) then
        local active = select(1, Activity.getActivity(peripheral))
        return active, true
    end

    return nil, false
end

local function buildMachineEntry(machine, idx, pType)
    local shortName = Activity.getShortName and Activity.getShortName(pType or machine.name) or (pType or machine.name)
    local shortLabel = machine.name:match("_(%d+)$") or (idx and tostring(idx)) or machine.name
    local fullLabel = shortName
    local idSuffix = machine.name:match("_(%d+)$")
    if idSuffix then
        fullLabel = shortName .. " #" .. idSuffix
    end

    return {
        label = shortLabel,
        shortName = shortName,
        fullLabel = fullLabel,
        name = machine.name,
        type = pType or machine.name,
        peripheral = machine.peripheral,
        isActive = false,
        energyPct = nil,
        crafting = nil,
        craftMethod = nil,
        craftUsesIndexed = false,
        noCraftSignals = false,
        polledAt = 0,
        craftPolledAt = 0,
        energyPolledAt = 0
    }
end

local function shouldPollMachine(entry, nowMs)
    if not entry then return true end
    local interval = entry.isActive and MACHINE_POLL_ACTIVE_MS or MACHINE_POLL_IDLE_MS
    return (nowMs - (entry.polledAt or 0)) >= interval
end

local function pollMachineEntry(entry, nowMs)
        local isActive = entry.isActive and true or false
        local isActivityKnown = false
        local p = entry.peripheral
        if p then
            local activeState, known = readActivityState(p)
            if known then
            isActivityKnown = true
            isActive = activeState and true or false
        end
    end

    if isActivityKnown then
        entry.isActive = isActive
    end
    local energyAge = nowMs - (entry.energyPolledAt or 0)
    if entry.isActive or entry.energyPct == nil or energyAge >= MACHINE_IDLE_ENERGY_POLL_MS then
        local energy = getEnergyPercent(p)
        if energy ~= nil then
            entry.energyPct = energy
            entry.energyPolledAt = nowMs
        end
    end

        if entry.isActive then
            local detectedCraft = getCraftingTarget(p, entry, true)
            if detectedCraft then
                entry.crafting = detectedCraft
            end
            entry.craftPolledAt = nowMs
        else
            local craftAge = nowMs - (entry.craftPolledAt or 0)
            if entry.crafting == nil or craftAge >= MACHINE_IDLE_CRAFT_POLL_MS then
                local detectedCraft = getCraftingTarget(p, entry, false)
                if detectedCraft then
                    entry.crafting = detectedCraft
                end
                entry.craftPolledAt = nowMs
            end
    end

    entry.polledAt = nowMs
    return entry
end

local function collectSectionMachines(self, typeData, nowMs, doSweep)
    local machines = {}
    local activeCount = 0
    local shared = self.sharedState
    local seen = shared.machineSeen

    for idx, machine in ipairs(typeData.machines) do
        local key = machine.name
        local entry = shared.machineEntries[key]

        if not entry then
            entry = buildMachineEntry(machine, idx, typeData.type)
            shared.machineEntries[key] = entry
        else
            entry.type = typeData.type
            entry.peripheral = machine.peripheral
            entry.label = machine.name:match("_(%d+)$") or entry.label
            if not entry.shortName then
                entry.shortName = Activity.getShortName and Activity.getShortName(typeData.type) or typeData.type
            end
            if not entry.fullLabel then
                entry.fullLabel = entry.shortName
                local idSuffix = machine.name:match("_(%d+)$")
                if idSuffix then
                    entry.fullLabel = entry.shortName .. " #" .. idSuffix
                end
            end
        end

        if doSweep and shouldPollMachine(entry, nowMs) then
            table.insert(shared.dueEntries, entry)
        end

        if entry.isActive then
            activeCount = activeCount + 1
        end

        if doSweep then
            seen[key] = true
        end
        table.insert(machines, entry)
        Yield.check(idx, 25)
    end

    return machines, activeCount
end

local function pollDueEntries(shared, nowMs, budget)
    local due = shared.dueEntries or {}
    local totalDue = #due
    if totalDue == 0 or budget <= 0 then
        return
    end

    local cursor = shared.pollCursor or 0
    local limit = math.min(budget, totalDue)
    local polled = 0
    for i = 1, limit do
        cursor = (cursor % totalDue) + 1
        local entry = due[cursor]
        if entry then
            pollMachineEntry(entry, nowMs)
            polled = polled + 1
        end
    end

    shared.pollCursor = cursor
    return polled
end

local function calculateSweepBudget(totalMachines, singleTypeMode)
    if totalMachines <= 0 then
        return 0
    end

    local minBudget = singleTypeMode and MIN_POLLS_PER_SWEEP_SINGLE or MIN_POLLS_PER_SWEEP_ALL
    local scaledBudget = math.ceil(totalMachines * 0.35)
    local maxBudget = singleTypeMode and 64 or 40

    return math.max(minBudget, math.min(maxBudget, scaledBudget))
end

local function countActiveMachines(machines)
    local active = 0
    for _, machine in ipairs(machines or {}) do
        if machine.isActive then
            active = active + 1
        end
    end
    return active
end

-- Draw a larger machine card:
-- - Left column: vertical power fill
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
        fill = math.floor(energyPct * cardHeight + 0.5)
    elseif isActive then
        fill = math.max(1, math.floor(cardHeight * 0.5))
    end
    if cardWidth >= 1 then
        monitor.setBackgroundColor(colors.gray)
        for row = 0, cardHeight - 1 do
            monitor.setCursorPos(x, y + row)
            monitor.write(" ")
        end

        if fill > 0 then
            monitor.setBackgroundColor(colors.lime)
            local fillRows = math.min(cardHeight, fill)
            local startRow = y + cardHeight - fillRows
            for row = startRow, y + cardHeight - 1 do
                monitor.setCursorPos(x, row)
                monitor.write(" ")
            end
        elseif isActive then
            monitor.setBackgroundColor(colors.green)
            for row = 0, cardHeight - 1 do
                monitor.setCursorPos(x, y + row)
                monitor.write(" ")
            end
        end
    end

    local contentX = x + (cardWidth > 1 and 1 or 0)
    local contentWidth = math.max(1, cardWidth - (cardWidth > 1 and 1 or 0))

    local idText = "#" .. tostring(machine.label or "?")
    idText = Text.truncateMiddle(idText, contentWidth)
    local idX = contentX + math.max(0, math.floor((contentWidth - #idText) / 2))
    local idY = y + 1
    monitor.setBackgroundColor(baseBg)
    monitor.setTextColor(colors.black)
    monitor.setCursorPos(idX, idY)
    monitor.write(idText)

    local craftText = ""
    if isActive and machine.crafting then
        craftText = Text.truncateMiddle(machine.crafting, contentWidth)
    elseif isActive then
        craftText = "Active"
    else
        craftText = "Idle"
    end

    craftText = Text.truncateMiddle(craftText, contentWidth)
    local craftX = contentX + math.max(0, math.floor((contentWidth - #craftText) / 2))
    local craftY = y + 2
    monitor.setCursorPos(craftX, craftY)
    monitor.write(craftText)

    monitor.setBackgroundColor(colors.black)
end

return BaseView.custom({
    sleepTime = 1,
    listenEvents = listenEvents,
    onEvent = nil,

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
        return true
    end,

    init = function(self, config)
        self.modFilter = config.mod_filter or "all"
        self.machineType = Activity.normalizeMachineType(config.machine_type)
    end,

    getData = function(self)
        -- Direct polling via MachineActivity (no snapshot bus)
        local types = Activity.buildTypeList(self.modFilter)
        local sections = {}
        local totalActive = 0
        local totalMachines = 0

        for _, typeInfo in ipairs(types) do
            if not self.machineType or typeInfo.type == self.machineType then
                local active = 0
                local machines = {}
                for idx, machine in ipairs(typeInfo.machines or {}) do
                    local isActive, _ = Activity.getActivity(machine.peripheral)
                    if isActive then active = active + 1 end
                    table.insert(machines, {
                        label = machine.name:match("_(%d+)$") or machine.name,
                        fullLabel = typeInfo.shortName .. " #" .. (machine.name:match("_(%d+)$") or tostring(idx)),
                        shortName = typeInfo.shortName,
                        name = machine.name,
                        type = typeInfo.type,
                        peripheral = machine.peripheral,
                        isActive = isActive and true or false,
                        energyPct = nil,
                        crafting = nil
                    })
                    Yield.check(idx, 10)
                end
                table.insert(sections, {
                    label = typeInfo.label,
                    color = typeInfo.classification and typeInfo.classification.color or colors.white,
                    active = active,
                    total = #machines,
                    machines = machines
                })
                totalActive = totalActive + active
                totalMachines = totalMachines + #machines
            end
        end

        return { sections = sections, totalActive = totalActive, totalMachines = totalMachines }
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

            self.monitor.setTextColor(resolveTextColor(section.color, colors.white))
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
