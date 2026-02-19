-- MachineSnapshotBus.lua
-- Shared machine telemetry cache and background poller.
-- Decouples machine state polling from per-monitor view render loops.

local Activity = mpm('peripherals/MachineActivity')
local Text = mpm('utils/Text')

local MachineSnapshotBus = {}

local DISCOVERY_REFRESH_MS = 5000
local SWEEP_INTERVAL_MS = 500
local ACTIVE_POLL_MS = 1000
local IDLE_POLL_MS = 1500
local IDLE_CRAFT_POLL_MS = 5000
local IDLE_ENERGY_POLL_MS = 5000
local MIN_SWEEP_BUDGET = 10
local MAX_SWEEP_BUDGET = 60

_G._shelfos_machineSnapshotBus = _G._shelfos_machineSnapshotBus or {
    running = false,
    refreshing = false,
    entriesByName = {},
    types = {},
    typeByName = {},
    pollCursor = 0,
    lastDiscoveryAt = 0,
    lastSweepAt = 0
}

local function state()
    return _G._shelfos_machineSnapshotBus
end

local function nowMs()
    return os.epoch("utc")
end

local function pause(seconds)
    local timer = os.startTimer(seconds or 0)
    repeat
        local _, tid = os.pullEvent("timer")
    until tid == timer
end

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

    local progress = safeCall(peripheral, "getRecipeProgress")
    if type(progress) == "number" then
        return progress > 0, nil, false
    end

    local indexedProgress = safeCall(peripheral, "getRecipeProgress", 0)
    if type(indexedProgress) == "number" then
        return indexedProgress > 0, 0, true
    end

    return false, nil, false
end

local function readCraftName(peripheral, methodName, process)
    if process ~= nil then
        return extractStackName(safeCall(peripheral, methodName, process))
    end
    return extractStackName(safeCall(peripheral, methodName))
end

local function getCraftingTarget(peripheral, entry)
    if not peripheral then return nil, false end

    local progressActive, bestProcess, usesIndexedProgress = detectProgressState(peripheral)
    if entry.craftMethod then
        local process = entry.craftUsesIndexed and bestProcess or nil
        local knownName = readCraftName(peripheral, entry.craftMethod, process)
        if knownName then
            return knownName, progressActive
        end
        entry.craftMethod = nil
        entry.craftUsesIndexed = false
    end

    if entry.noCraftSignals and not progressActive then
        return nil, progressActive
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
        if not candidate.indexed or (usesIndexedProgress and bestProcess ~= nil) then
            local process = candidate.indexed and bestProcess or nil
            local outputName = readCraftName(peripheral, candidate.method, process)
            if outputName then
                entry.craftMethod = candidate.method
                entry.craftUsesIndexed = candidate.indexed
                entry.noCraftSignals = false
                return outputName, progressActive
            end
        end
    end

    entry.noCraftSignals = true
    return nil, progressActive
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

local function buildEntry(machine, pType, classification)
    local shortName = Activity.getShortName and Activity.getShortName(pType or machine.name) or (pType or machine.name)
    local shortLabel = machine.name:match("_(%d+)$") or machine.name
    local fullLabel = shortName
    local idSuffix = machine.name:match("_(%d+)$")
    if idSuffix then
        fullLabel = shortName .. " #" .. idSuffix
    end

    return {
        name = machine.name,
        type = pType or machine.name,
        classification = classification or Activity.classify(pType or machine.name),
        shortName = shortName,
        label = shortLabel,
        fullLabel = fullLabel,
        peripheral = machine.peripheral,
        isActive = false,
        activity = {},
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

local function sortByMachineName(a, b)
    local aId = tonumber((a.name or ""):match("_(%d+)$") or "")
    local bId = tonumber((b.name or ""):match("_(%d+)$") or "")
    if aId and bId and aId ~= bId then
        return aId < bId
    end
    return tostring(a.name or "") < tostring(b.name or "")
end

local function rebuildTypes()
    local st = state()
    st.types = {}
    st.typeByName = {}

    for _, entry in pairs(st.entriesByName) do
        local typeInfo = st.typeByName[entry.type]
        if not typeInfo then
            typeInfo = {
                type = entry.type,
                label = (entry.classification and entry.classification.mod == "mi")
                    and ("MI: " .. entry.shortName) or entry.shortName,
                shortName = entry.shortName,
                classification = entry.classification,
                machines = {}
            }
            st.typeByName[entry.type] = typeInfo
            table.insert(st.types, typeInfo)
        end
        table.insert(typeInfo.machines, entry)
    end

    for _, typeInfo in ipairs(st.types) do
        table.sort(typeInfo.machines, sortByMachineName)
    end
    table.sort(st.types, function(a, b) return a.label < b.label end)
end

local function refreshDiscovery()
    local st = state()
    if st.refreshing then
        return false
    end

    st.refreshing = true
    local before = nowMs()
    local discovered = Activity.discoverAll()
    if type(discovered) ~= "table" then
        st.refreshing = false
        return false
    end

    local seen = {}
    for pType, data in pairs(discovered) do
        local classification = data.classification or Activity.classify(pType)
        for _, machine in ipairs(data.machines or {}) do
            local entry = st.entriesByName[machine.name]
            if not entry then
                entry = buildEntry(machine, pType, classification)
                st.entriesByName[machine.name] = entry
            else
                entry.type = pType
                entry.classification = classification
                entry.shortName = Activity.getShortName and Activity.getShortName(pType) or pType
                entry.peripheral = machine.peripheral
            end
            seen[machine.name] = true
        end
    end

    for name in pairs(st.entriesByName) do
        if not seen[name] then
            st.entriesByName[name] = nil
        end
    end

    rebuildTypes()
    st.lastDiscoveryAt = before
    st.refreshing = false
    return true
end

local function shouldPollEntry(entry, now)
    local interval = entry.isActive and ACTIVE_POLL_MS or IDLE_POLL_MS
    return (now - (entry.polledAt or 0)) >= interval
end

local function pollEntry(entry, now)
    local isActive, activityData = Activity.getActivity(entry.peripheral)
    if type(isActive) == "boolean" then
        entry.isActive = isActive
    end
    entry.activity = type(activityData) == "table" and activityData or {}

    local energyAge = now - (entry.energyPolledAt or 0)
    if entry.isActive or entry.energyPct == nil or energyAge >= IDLE_ENERGY_POLL_MS then
        local energy = getEnergyPercent(entry.peripheral)
        if energy ~= nil then
            entry.energyPct = energy
            entry.energyPolledAt = now
        end
    end

    if entry.isActive then
        local detectedCraft, progressActive = getCraftingTarget(entry.peripheral, entry)
        if progressActive then
            entry.isActive = true
        end
        if detectedCraft then
            entry.crafting = detectedCraft
        end
        entry.craftPolledAt = now
    else
        local craftAge = now - (entry.craftPolledAt or 0)
        if entry.crafting == nil or craftAge >= IDLE_CRAFT_POLL_MS then
            local detectedCraft = getCraftingTarget(entry.peripheral, entry)
            if detectedCraft then
                entry.crafting = detectedCraft
            end
            entry.craftPolledAt = now
        end
    end

    entry.polledAt = now
end

local function pollSweep()
    local st = state()
    local now = nowMs()
    local due = {}
    for _, entry in pairs(st.entriesByName) do
        if shouldPollEntry(entry, now) then
            table.insert(due, entry)
        end
    end

    local total = #due
    if total == 0 then
        return false
    end

    local budget = math.max(MIN_SWEEP_BUDGET, math.min(MAX_SWEEP_BUDGET, math.ceil(total * 0.35)))
    local limit = math.min(budget, total)
    local cursor = st.pollCursor or 0
    for i = 1, limit do
        cursor = (cursor % total) + 1
        local entry = due[cursor]
        if entry then
            pollEntry(entry, now)
        end
        if i % 4 == 0 then
            pause(0)
        end
    end

    st.pollCursor = cursor
    st.lastSweepAt = now
    return true
end

function MachineSnapshotBus.isRunning()
    return state().running == true
end

function MachineSnapshotBus.tick(force)
    local st = state()
    local now = nowMs()
    local didWork = false

    if force or (now - (st.lastDiscoveryAt or 0)) >= DISCOVERY_REFRESH_MS then
        if refreshDiscovery() then
            didWork = true
        end
    end

    if force or (now - (st.lastSweepAt or 0)) >= SWEEP_INTERVAL_MS then
        if pollSweep() then
            didWork = true
        end
    end

    return didWork
end

function MachineSnapshotBus.runLoop(runningRef)
    local st = state()
    st.running = true

    while runningRef.value do
        local didWork = MachineSnapshotBus.tick(false)
        if not didWork then
            pause(0.1)
        end
    end

    st.running = false
end

function MachineSnapshotBus.invalidate()
    local st = state()
    st.lastDiscoveryAt = 0
    st.lastSweepAt = 0
    Activity.invalidateCache()
end

local function matchesFilter(typeInfo, modFilter)
    if not typeInfo then return false end
    if not modFilter or modFilter == "all" then return true end
    return typeInfo.classification and typeInfo.classification.mod == modFilter
end

function MachineSnapshotBus.getTypeList(modFilter)
    local st = state()
    local out = {}
    for _, typeInfo in ipairs(st.types or {}) do
        if matchesFilter(typeInfo, modFilter) then
            table.insert(out, typeInfo)
        end
    end
    return out
end

function MachineSnapshotBus.getSnapshot(modFilter, machineType)
    local st = state()
    local sections = {}
    local totalActive = 0
    local totalMachines = 0

    local function addType(typeInfo)
        local active = 0
        for _, machine in ipairs(typeInfo.machines or {}) do
            if machine.isActive then
                active = active + 1
            end
        end

        table.insert(sections, {
            label = typeInfo.label,
            color = typeInfo.classification and typeInfo.classification.color or colors.white,
            active = active,
            total = #(typeInfo.machines or {}),
            machines = typeInfo.machines or {}
        })

        totalActive = totalActive + active
        totalMachines = totalMachines + #(typeInfo.machines or {})
    end

    if machineType then
        local typeInfo = st.typeByName and st.typeByName[machineType] or nil
        if typeInfo and matchesFilter(typeInfo, modFilter) then
            addType(typeInfo)
        end
    else
        for _, typeInfo in ipairs(st.types or {}) do
            if matchesFilter(typeInfo, modFilter) then
                addType(typeInfo)
            end
        end
    end

    return {
        sections = sections,
        totalActive = totalActive,
        totalMachines = totalMachines,
        generatedAt = nowMs()
    }
end

return MachineSnapshotBus
