-- DependencyStatus.lua
-- Tracks remote peripheral dependency health per render context.
-- Context format is caller-defined (e.g., "monitor_0|ItemChanges").

local DependencyStatus = {}

_G._shelfos_dependencyStatus = _G._shelfos_dependencyStatus or {
    byContext = {}
}

local ENTRY_TTL_MS = 90000
local ERROR_HOLD_MS = 12000

local function nowMs()
    return os.epoch("utc")
end

local function getEntry(contextKey, peripheralName)
    if not contextKey or not peripheralName then
        return nil
    end

    local store = _G._shelfos_dependencyStatus
    local ctx = store.byContext[contextKey]
    if not ctx then
        ctx = {}
        store.byContext[contextKey] = ctx
    end

    local entry = ctx[peripheralName]
    if not entry then
        entry = {
            name = peripheralName,
            state = "ok",
            updatedAt = 0,
            successAt = 0,
            errorAt = 0,
            pendingAt = 0,
            latencyMs = nil,
            lastError = nil
        }
        ctx[peripheralName] = entry
    end

    return entry
end

local function touch(entry)
    entry.updatedAt = nowMs()
end

function DependencyStatus.markPending(contextKey, peripheralName)
    local entry = getEntry(contextKey, peripheralName)
    if not entry then return end

    entry.state = "pending"
    entry.pendingAt = nowMs()
    touch(entry)
end

function DependencyStatus.markCached(contextKey, peripheralName, ageMs, isStale)
    local entry = getEntry(contextKey, peripheralName)
    if not entry then return end

    entry.latencyMs = ageMs
    if isStale then
        entry.state = "pending"
        entry.pendingAt = nowMs()
    else
        entry.state = "ok"
        entry.successAt = nowMs()
    end
    touch(entry)
end

function DependencyStatus.markSuccess(contextKey, peripheralName, latencyMs)
    local entry = getEntry(contextKey, peripheralName)
    if not entry then return end

    entry.state = "ok"
    entry.successAt = nowMs()
    entry.latencyMs = latencyMs
    entry.lastError = nil
    touch(entry)
end

function DependencyStatus.markError(contextKey, peripheralName, err)
    local entry = getEntry(contextKey, peripheralName)
    if not entry then return end

    entry.state = "error"
    entry.errorAt = nowMs()
    entry.lastError = tostring(err or "error")
    touch(entry)
end

function DependencyStatus.getContext(contextKey)
    local store = _G._shelfos_dependencyStatus
    local ctx = store.byContext[contextKey]
    if not ctx then
        return {}
    end

    local now = nowMs()
    local out = {}
    local hasEntries = false

    for name, entry in pairs(ctx) do
        if (now - (entry.updatedAt or 0)) > ENTRY_TTL_MS then
            ctx[name] = nil
        else
            hasEntries = true
            local state = entry.state or "ok"
            if state == "error" and (now - (entry.errorAt or 0)) > ERROR_HOLD_MS then
                state = "ok"
            end
            table.insert(out, {
                name = name,
                state = state,
                latencyMs = entry.latencyMs,
                lastError = entry.lastError
            })
        end
    end

    if not hasEntries then
        store.byContext[contextKey] = nil
    end

    table.sort(out, function(a, b)
        return a.name < b.name
    end)

    return out
end

return DependencyStatus
