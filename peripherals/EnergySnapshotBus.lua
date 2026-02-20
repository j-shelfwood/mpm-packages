-- EnergySnapshotBus.lua
-- Shared energy storage discovery + polling cache.
-- Decouples heavy energy reads from per-monitor view render loops.

local Peripherals = mpm('utils/Peripherals')
local Yield = mpm('utils/Yield')

local EnergySnapshotBus = {}

local DISCOVERY_REFRESH_MS = 5000
local SWEEP_INTERVAL_MS = 500
local POLL_INTERVAL_MS = 1500
local ERROR_POLL_INTERVAL_MS = 3000

_G._shelfos_energySnapshotBus = _G._shelfos_energySnapshotBus or {
    running = false,
    refreshing = false,
    entriesByName = {},
    orderedNames = {},
    pollCursor = 0,
    lastDiscoveryAt = 0,
    lastSweepAt = 0
}

local STORAGE_PATTERNS = {
    "energy_cube", "energycube", "battery", "energy_cell", "energycell",
    "capacitor", "accumulator", "flux_storage", "fluxstorage", "induction"
}

local function state()
    return _G._shelfos_energySnapshotBus
end

local function nowMs()
    return os.epoch("utc")
end

local function joulesToFE(value)
    if type(mekanismEnergyHelper) == "table" and type(mekanismEnergyHelper.joulesToFE) == "function" then
        local ok, converted = pcall(mekanismEnergyHelper.joulesToFE, value)
        if ok and type(converted) == "number" then
            return converted
        end
    end
    return value / 2.5
end

local function hasEnergyMethods(p)
    if not p then return false end
    if type(p.getEnergy) ~= "function" then return false end
    if type(p.getEnergyCapacity) == "function" then return true end
    if type(p.getMaxEnergy) == "function" then return true end
    return false
end

local function isLikelyStorageType(typeName, peripheralName)
    local id = (typeName or peripheralName or ""):lower()
    for _, pattern in ipairs(STORAGE_PATTERNS) do
        if id:find(pattern) then
            return true
        end
    end
    return false
end

local function pollStatus(entry)
    local p = entry.peripheral
    if not p then
        return false
    end

    local status = {
        stored = 0,
        capacity = 0,
        percent = 0,
        unit = "FE",
        storedFE = 0,
        capacityFE = 0
    }

    local started = nowMs()
    local storedOk, stored = pcall(p.getEnergy)
    local capacityOk, capacity = pcall(p.getEnergyCapacity)

    if storedOk and capacityOk and type(stored) == "number" and type(capacity) == "number" then
        status.stored = stored
        status.capacity = capacity > 0 and capacity or 1
        status.percent = status.capacity > 0 and (status.stored / status.capacity) or 0
        status.storedFE = status.stored
        status.capacityFE = status.capacity
    else
        storedOk, stored = pcall(p.getEnergy)
        local maxOk, max = pcall(p.getMaxEnergy)
        if storedOk and maxOk and type(stored) == "number" and type(max) == "number" then
            status.stored = stored
            status.capacity = max > 0 and max or 1
            status.percent = status.capacity > 0 and (status.stored / status.capacity) or 0
            status.unit = "J"
            status.storedFE = joulesToFE(status.stored)
            status.capacityFE = joulesToFE(status.capacity)
        else
            return false
        end
    end

    local finished = nowMs()
    entry.status = {
        ok = true,
        data = status,
        updatedAt = finished,
        latencyMs = finished - started
    }
    return true
end

local function refreshDiscovery()
    local st = state()
    if st.refreshing then
        return false
    end
    st.refreshing = true

    local ok, changed = pcall(function()
        local names = Peripherals.getNames()
        local seen = {}
        local didChange = false

        for idx, name in ipairs(names) do
            local primaryType = Peripherals.getType(name)
            local hasEnergyStorageType = Peripherals.hasType(name, "energy_storage")
            local p = Peripherals.wrap(name)
            local isStorage = hasEnergyStorageType or isLikelyStorageType(primaryType, name)

            if isStorage and hasEnergyMethods(p) then
                seen[name] = true
                local entry = st.entriesByName[name]
                if not entry then
                    st.entriesByName[name] = {
                        name = name,
                        primaryType = primaryType or (hasEnergyStorageType and "energy_storage" or "unknown_storage"),
                        peripheral = p,
                        status = nil,
                        nextPollAt = 0
                    }
                    didChange = true
                else
                    entry.primaryType = primaryType or entry.primaryType
                    entry.peripheral = p
                end
            end

            if idx % 25 == 0 then
                Yield.sleep(0)
            end
        end

        for name in pairs(st.entriesByName) do
            if not seen[name] then
                st.entriesByName[name] = nil
                didChange = true
            end
        end

        if didChange then
            st.orderedNames = {}
            for name in pairs(st.entriesByName) do
                table.insert(st.orderedNames, name)
            end
            table.sort(st.orderedNames)
            if st.pollCursor > #st.orderedNames then
                st.pollCursor = 0
            end
        end

        st.lastDiscoveryAt = nowMs()
        return didChange
    end)

    st.refreshing = false
    if not ok then
        return false
    end
    return changed
end

local function pollSweep()
    local st = state()
    local ordered = st.orderedNames
    local total = #ordered
    if total == 0 then
        st.lastSweepAt = nowMs()
        return false
    end

    local now = nowMs()
    local didWork = false
    local cursor = st.pollCursor or 0
    local budget = math.min(total, 24)

    for i = 1, budget do
        cursor = (cursor % total) + 1
        local name = ordered[cursor]
        local entry = st.entriesByName[name]
        if entry then
            local dueAt = entry.nextPollAt or 0
            if now >= dueAt then
                local ok = pollStatus(entry)
                if ok then
                    entry.nextPollAt = now + POLL_INTERVAL_MS
                else
                    entry.nextPollAt = now + ERROR_POLL_INTERVAL_MS
                end
                didWork = true
            end
        end

        if i % 6 == 0 then
            Yield.sleep(0)
        end
    end

    st.pollCursor = cursor
    st.lastSweepAt = now
    return didWork
end

function EnergySnapshotBus.isRunning()
    return state().running == true
end

function EnergySnapshotBus.invalidate()
    local st = state()
    st.lastDiscoveryAt = 0
    st.lastSweepAt = 0
end

function EnergySnapshotBus.tick(force)
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

function EnergySnapshotBus.runLoop(runningRef)
    local st = state()
    st.running = true

    while runningRef.value do
        local didWork = EnergySnapshotBus.tick(false)
        if not didWork then
            Yield.sleep(0.1)
        end
    end

    st.running = false
end

function EnergySnapshotBus.getEntries()
    local st = state()
    local out = {}
    for _, name in ipairs(st.orderedNames or {}) do
        local entry = st.entriesByName[name]
        if entry then
            table.insert(out, entry)
        end
    end
    return out
end

function EnergySnapshotBus.getStatusByName(name)
    local entry = state().entriesByName[name]
    if not entry then return nil end
    return entry.status
end

function EnergySnapshotBus.getStatusByPeripheral(peripheral)
    local name = Peripherals.getName(peripheral)
    if not name then return nil end
    return EnergySnapshotBus.getStatusByName(name)
end

return EnergySnapshotBus
