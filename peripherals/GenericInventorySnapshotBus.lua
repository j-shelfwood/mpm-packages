-- GenericInventorySnapshotBus.lua
-- Snapshot bus for vanilla/CC:Tweaked inventories.

local Peripherals = mpm('utils/Peripherals')
local Yield = mpm('utils/Yield')

local GenericInventorySnapshotBus = {}

local DISCOVERY_REFRESH_MS = 5000
local SWEEP_INTERVAL_MS = 500
local POLL_INTERVAL_MS = 2000
local ERROR_POLL_INTERVAL_MS = 4000
local MIN_SWEEP_BUDGET = 10
local MAX_SWEEP_BUDGET = 40

_G._shelfos_inventorySnapshotBus = _G._shelfos_inventorySnapshotBus or {
    running = false,
    refreshing = false,
    entriesByName = {},
    orderedNames = {},
    pollCursor = 0,
    lastDiscoveryAt = 0,
    lastSweepAt = 0
}

local function state()
    return _G._shelfos_inventorySnapshotBus
end

local function nowMs()
    return os.epoch("utc")
end

local function dataHash(value)
    if type(value) == "table" then
        local ok, serialized = pcall(textutils.serialize, value)
        if ok and serialized then
            return serialized
        end
    end
    return tostring(value)
end

local function hasMethod(methods, name)
    if type(methods) ~= "table" then
        return false
    end
    for _, method in ipairs(methods) do
        if method == name then
            return true
        end
    end
    return false
end

local function isInventoryCandidate(name, methods)
    if not hasMethod(methods, "list") then
        return false
    end
    return Peripherals.hasType(name, "inventory") or
        Peripherals.hasType(name, "chest") or
        Peripherals.hasType(name, "barrel") or
        Peripherals.hasType(name, "drawer") or
        Peripherals.hasType(name, "shulker") or
        Peripherals.hasType(name, "container") or
        Peripherals.hasType(name, "storage") or
        hasMethod(methods, "size") or
        hasMethod(methods, "getItemDetail")
end

local function ensureRemoteSubscription(entry)
    if entry.subscribed then
        return
    end
    local p = entry.peripheral
    if type(p) == "table" and type(p.subscribe) == "function" then
        pcall(p.subscribe, "list", {}, POLL_INTERVAL_MS, "inventory_snapshot_updated")
        entry.subscribed = true
    end
end

local function pollInventory(entry)
    local p = entry.peripheral
    if not p or type(p.list) ~= "function" then
        return false
    end
    local ok, snapshot = pcall(p.list)
    if not ok then
        return false
    end
    local hash = dataHash(snapshot)
    if hash ~= entry.snapshotHash then
        entry.snapshotHash = hash
        entry.snapshot = snapshot
        pcall(os.queueEvent, "inventory_snapshot_updated", entry.name, "list", {snapshot}, {
            resultHash = hash
        })
    end
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
            local methods = Peripherals.getMethods(name)
            if isInventoryCandidate(name, methods) then
                seen[name] = true
                local entry = st.entriesByName[name]
                local p = Peripherals.wrap(name)
                local isRemote = type(p) == "table" and p._isRemote == true
                if not entry then
                    st.entriesByName[name] = {
                        name = name,
                        primaryType = Peripherals.getType(name),
                        methods = methods,
                        peripheral = p,
                        isRemote = isRemote,
                        subscribed = false,
                        snapshot = nil,
                        snapshotHash = nil,
                        nextPollAt = 0
                    }
                    didChange = true
                else
                    entry.primaryType = Peripherals.getType(name) or entry.primaryType
                    entry.methods = methods
                    entry.peripheral = p
                    entry.isRemote = isRemote
                    if not isRemote then
                        entry.subscribed = false
                    end
                end
            end

            if idx % 25 == 0 then
                Yield.sleep(0)
            end
        end

        for name, entry in pairs(st.entriesByName) do
            if not seen[name] then
                if entry.isRemote and entry.subscribed and entry.peripheral and type(entry.peripheral.unsubscribe) == "function" then
                    pcall(entry.peripheral.unsubscribe, "list", {})
                end
                st.entriesByName[name] = nil
                didChange = true
            end
        end

        if didChange then
            st.orderedNames = {}
            for name, entry in pairs(st.entriesByName) do
                if not entry.isRemote then
                    table.insert(st.orderedNames, name)
                end
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
    local budget = math.min(total, MAX_SWEEP_BUDGET)
    if budget < MIN_SWEEP_BUDGET then
        budget = total
    end

    for _ = 1, budget do
        cursor = (cursor % total) + 1
        local name = ordered[cursor]
        local entry = st.entriesByName[name]
        if entry then
            if now >= (entry.nextPollAt or 0) then
                local ok = pollInventory(entry)
                entry.nextPollAt = now + (ok and POLL_INTERVAL_MS or ERROR_POLL_INTERVAL_MS)
                didWork = true
                Yield.sleep(0)
            end
        end
    end

    st.pollCursor = cursor
    st.lastSweepAt = now
    return didWork
end

function GenericInventorySnapshotBus.runLoop(runningRef)
    local st = state()
    st.running = true

    while runningRef.value do
        local now = nowMs()
        local didWork = false

        if (now - (st.lastDiscoveryAt or 0)) >= DISCOVERY_REFRESH_MS then
            if refreshDiscovery() then
                didWork = true
            end
        end

        for _, entry in pairs(st.entriesByName) do
            if entry.isRemote then
                ensureRemoteSubscription(entry)
            end
        end

        if (now - (st.lastSweepAt or 0)) >= SWEEP_INTERVAL_MS then
            if pollSweep() then
                didWork = true
            end
        end

        if not didWork then
            Yield.sleep(0.1)
        end
    end

    st.running = false
end

return GenericInventorySnapshotBus
