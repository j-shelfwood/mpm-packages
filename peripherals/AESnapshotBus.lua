-- AESnapshotBus.lua
-- Shared AE2 snapshot cache and background poller.
-- Decouples heavy bridge reads from monitor render loops.

local Peripherals = mpm('utils/Peripherals')
local Yield = mpm('utils/Yield')
local EventUtils = mpm('utils/EventUtils')

local AESnapshotBus = {}

_G._shelfos_aeSnapshotBus = _G._shelfos_aeSnapshotBus or {
    entries = {},
    running = false
}

local POLL_PLAN = {
    -- Heavy payloads
    { key = "items", intervalMs = 3000, fn = function(bridge) return bridge.getItems and (bridge.getItems() or {}) or {} end },
    { key = "fluids", intervalMs = 3000, fn = function(bridge) return bridge.getFluids and (bridge.getFluids() or {}) or {} end },
    { key = "chemicals", intervalMs = 4000, fn = function(bridge)
        if not bridge.getChemicals then return {} end
        return bridge.getChemicals() or {}
    end },

    -- Medium payloads
    { key = "craftingTasks", intervalMs = 2000, fn = function(bridge) return bridge.getCraftingTasks and (bridge.getCraftingTasks() or {}) or {} end },
    { key = "craftingCPUs", intervalMs = 3000, fn = function(bridge) return bridge.getCraftingCPUs and (bridge.getCraftingCPUs() or {}) or {} end },
    { key = "cells", intervalMs = 6000, fn = function(bridge) return bridge.getCells and (bridge.getCells() or {}) or {} end },
    { key = "drives", intervalMs = 6000, fn = function(bridge) return bridge.getDrives and (bridge.getDrives() or {}) or {} end },
    { key = "patterns", intervalMs = 8000, fn = function(bridge) return bridge.getPatterns and (bridge.getPatterns() or {}) or {} end },
    { key = "craftableItems", intervalMs = 8000, fn = function(bridge) return bridge.getCraftableItems and (bridge.getCraftableItems() or {}) or {} end },

    -- Light payloads
    { key = "energy", intervalMs = 1200, fn = function(bridge)
        return {
            stored = (bridge.getStoredEnergy and bridge.getStoredEnergy()) or 0,
            capacity = (bridge.getEnergyCapacity and bridge.getEnergyCapacity()) or 0,
            usage = (bridge.getEnergyUsage and bridge.getEnergyUsage()) or 0
        }
    end },
    { key = "itemStorage", intervalMs = 1800, fn = function(bridge)
        return {
            used = (bridge.getUsedItemStorage and bridge.getUsedItemStorage()) or 0,
            total = (bridge.getTotalItemStorage and bridge.getTotalItemStorage()) or 0,
            available = (bridge.getAvailableItemStorage and bridge.getAvailableItemStorage()) or 0
        }
    end },
    { key = "fluidStorage", intervalMs = 1800, fn = function(bridge)
        return {
            used = (bridge.getUsedFluidStorage and bridge.getUsedFluidStorage()) or 0,
            total = (bridge.getTotalFluidStorage and bridge.getTotalFluidStorage()) or 0,
            available = (bridge.getAvailableFluidStorage and bridge.getAvailableFluidStorage()) or 0
        }
    end },
    { key = "averageEnergyInput", intervalMs = 2000, fn = function(bridge)
        return (bridge.getAverageEnergyInput and bridge.getAverageEnergyInput()) or 0
    end },
}

local function nowMs()
    return os.epoch("utc")
end

local function bridgeName(bridge)
    if not bridge then return nil end
    return Peripherals.getName(bridge)
end

local function getStore()
    return _G._shelfos_aeSnapshotBus
end

local function ensureEntry(bridge)
    local name = bridgeName(bridge)
    if not name then return nil end

    local store = getStore()
    local entry = store.entries[name]
    if not entry then
        entry = {
            name = name,
            bridge = bridge,
            cache = {},
            nextAt = {},
            lastSeenAt = nowMs()
        }
        store.entries[name] = entry
    else
        entry.bridge = bridge
        entry.lastSeenAt = nowMs()
    end

    return entry
end

function AESnapshotBus.registerBridge(bridge)
    ensureEntry(bridge)
end

function AESnapshotBus.isRunning()
    return getStore().running == true
end

function AESnapshotBus.get(bridge, key)
    local entry = ensureEntry(bridge)
    if not entry then return nil end
    return entry.cache[key]
end

function AESnapshotBus.peekByName(name, key)
    local entry = getStore().entries[name]
    if not entry then return nil end
    return entry.cache[key]
end

local function pollOne(entry, spec, now)
    local dueAt = entry.nextAt[spec.key] or 0
    if now < dueAt then
        return false
    end

    entry.nextAt[spec.key] = now + spec.intervalMs
    local started = nowMs()
    local ok, data = pcall(spec.fn, entry.bridge)
    local finished = nowMs()

    if ok then
        entry.cache[spec.key] = {
            ok = true,
            data = data,
            updatedAt = finished,
            latencyMs = finished - started
        }
    else
        local prev = entry.cache[spec.key]
        entry.cache[spec.key] = {
            ok = false,
            data = prev and prev.data or nil,
            updatedAt = finished,
            latencyMs = finished - started,
            error = tostring(data)
        }
    end

    return true
end

function AESnapshotBus.runLoop(runningRef)
    local store = getStore()
    store.running = true

    while runningRef.value do
        local now = nowMs()
        local didWork = false

        for _, entry in pairs(store.entries) do
            for _, spec in ipairs(POLL_PLAN) do
                if pollOne(entry, spec, now) then
                    didWork = true
                    Yield.yield()
                end
            end
        end

        if not didWork then
            local t = os.startTimer(0.1)
            repeat
                local _, tid = EventUtils.pullEvent("timer")
            until tid == t
        end
    end

    store.running = false
end

return AESnapshotBus
