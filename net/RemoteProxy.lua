-- RemoteProxy.lua
-- Creates a proxy object that looks like a real peripheral
-- but forwards method calls over the network
-- Includes result caching for non-blocking reads and auto-reconnect with backoff
--
-- CACHE ARCHITECTURE:
-- Remote peripheral calls are expensive (RPC over ender modem, 50-200ms best case,
-- 2s timeout worst case). Views call methods every render cycle (1s).
-- To avoid blocking render paths:
--   1. First call: blocking RPC to populate initial cache
--   2. Subsequent calls: return cached value instantly
--   3. If cache is stale: fire async refresh via network loop, still return cache
--   4. Cache updated when PERIPH_RESULT arrives via KernelNetwork loop
-- Result: views always get instant responses, data is at most 1 refresh cycle stale.

local Protocol = mpm('net/Protocol')
local RenderContext = mpm('net/RenderContext')
local DependencyStatus = mpm('net/DependencyStatus')
local EventUtils = mpm('utils/EventUtils')

local RemoteProxy = {}

-- Reconnection settings
local MAX_CONSECUTIVE_FAILURES = 3   -- Disconnect after this many consecutive failures
local RECONNECT_COOLDOWN_MS = 10000  -- Wait 10 seconds before auto-reconnect attempt

-- Cache settings
local CACHE_TTL_MS = 2000            -- Return cache if fresher than 2s (covers 2 render cycles)
local CACHE_STALE_MS = 5000          -- Fire async refresh after 5s staleness
local CACHE_EXPIRE_MS = 30000        -- Discard cache after 30s (peripheral may be gone)
local ASYNC_RETRY_MS = 1000          -- Avoid burst retries when refresh fails/lag spikes

-- Default RPC timeout in seconds (only used for initial blocking call)
-- 3s allows time for host to process if busy with another heavy request
local DEFAULT_TIMEOUT = 3

-- Methods that return large payloads and need extended timeouts
local HEAVY_METHOD_TIMEOUT = {
    getItems = 5,
    getFluids = 5,
    getChemicals = 5,
    getCraftableItems = 5,
    getCraftableFluids = 5,
    getCraftableChemicals = 5,
    getPatterns = 5,
    getCells = 3,
    getDrives = 3,
}

-- Methods that should never be cached (they perform actions, not reads)
local NO_CACHE_METHODS = {
    craftItem = true,
    exportItem = true,
    importItem = true,
    exportFluid = true,
    importFluid = true,
    exportItemToPeripheral = true,
    importItemFromPeripheral = true,
}

-- Create a proxy for a remote peripheral
-- @param client PeripheralClient instance
-- @param hostId Computer ID of the host
-- @param name Peripheral name
-- @param pType Peripheral type
-- @param methods Array of method names
-- @return Proxy table that mimics the peripheral
function RemoteProxy.create(client, hostId, name, pType, methods)
    local proxy = {}

    -- Metadata (prefixed with _ to avoid conflicts)
    proxy._isRemote = true
    proxy._hostId = hostId
    proxy._name = name
    proxy._type = pType
    proxy._client = client
    proxy._connected = true

    -- Reconnection state
    proxy._failureCount = 0
    proxy._lastFailureTime = 0
    proxy._reconnecting = false

    -- Result cache: { [methodKey] = { results = {...}, timestamp = epoch_ms } }
    proxy._cache = {}
    -- Track in-flight async requests to avoid duplicate sends
    proxy._pending = {}
    proxy._nextRefreshAt = {}

    -- Auto-reconnect if disconnected and cooldown has elapsed
    local function ensureConnected()
        if proxy._connected then
            return true
        end

        local now = os.epoch("utc")
        if now - proxy._lastFailureTime < RECONNECT_COOLDOWN_MS then
            return false
        end

        if proxy._reconnecting then
            return false
        end

        proxy._reconnecting = true
        local found = client:rediscover(name)
        proxy._reconnecting = false

        if found then
            proxy._connected = true
            proxy._hostId = found.hostId
            proxy._failureCount = 0
            return true
        end

        proxy._lastFailureTime = now
        return false
    end

    -- Build a cache key from method name + args
    local function cacheKey(methodName, args)
        if not args or #args == 0 then
            return methodName
        end
        -- Simple key: method_arg1_arg2 (sufficient for peripheral APIs)
        local parts = { methodName }
        for _, a in ipairs(args) do
            table.insert(parts, tostring(a))
        end
        return table.concat(parts, "_")
    end

    -- Generate method stubs for each available method
    for _, methodName in ipairs(methods) do
        proxy[methodName] = function(...)
            local contextKey = RenderContext.get()
            if not ensureConnected() then
                if contextKey then
                    DependencyStatus.markError(contextKey, name, "disconnected")
                end
                return nil
            end

            local args = {...}
            local timeout = HEAVY_METHOD_TIMEOUT[methodName] or DEFAULT_TIMEOUT

            -- Action methods (craft, export, import) are never cached
            if NO_CACHE_METHODS[methodName] then
                local startedAt = os.epoch("utc")
                local results, err = client:call(proxy._hostId, name, methodName, args, timeout)
                if err then
                    proxy._failureCount = proxy._failureCount + 1
                    proxy._lastFailureTime = os.epoch("utc")
                    if proxy._failureCount >= MAX_CONSECUTIVE_FAILURES then
                        proxy._connected = false
                    end
                    if contextKey then
                        DependencyStatus.markError(contextKey, name, err)
                    end
                    return nil
                end
                proxy._failureCount = 0
                if contextKey then
                    DependencyStatus.markSuccess(contextKey, name, os.epoch("utc") - startedAt)
                end
                if results and #results > 0 then
                    return table.unpack(results)
                end
                return nil
            end

            -- Read methods: use cache-first pattern
            local key = cacheKey(methodName, args)
            local now = os.epoch("utc")
            local cached = proxy._cache[key]
            local age = cached and (now - cached.timestamp) or nil

            -- Return cached value if fresh enough
            if cached and age < CACHE_TTL_MS then
                if contextKey then
                    DependencyStatus.markCached(contextKey, name, age, false)
                end
                if cached.results and #cached.results > 0 then
                    return table.unpack(cached.results)
                end
                return nil
            end

            -- Cache exists but stale: return stale value, fire async refresh
            if cached and age < CACHE_EXPIRE_MS then
                if contextKey then
                    DependencyStatus.markCached(contextKey, name, age, age >= CACHE_STALE_MS)
                end
                -- Fire async refresh if not already in-flight
                local shouldRefresh = age >= CACHE_STALE_MS and now >= (proxy._nextRefreshAt[key] or 0)
                if shouldRefresh and not proxy._pending[key] then
                    proxy._pending[key] = true
                    proxy._nextRefreshAt[key] = now + ASYNC_RETRY_MS
                    local callbackContext = contextKey
                    if callbackContext then
                        DependencyStatus.markPending(callbackContext, name)
                    end
                    client:callAsync(proxy._hostId, name, methodName, args, function(results, err)
                        proxy._pending[key] = nil
                        if err then
                            -- Async refresh is opportunistic — don't increment failureCount
                            -- The stale cached value is still being served to views
                            -- Only blocking call failures should count toward disconnect
                            if callbackContext then
                                DependencyStatus.markError(callbackContext, name, err)
                            end
                            return
                        end
                        proxy._failureCount = 0
                        proxy._nextRefreshAt[key] = 0
                        proxy._cache[key] = {
                            results = results,
                            timestamp = os.epoch("utc")
                        }
                        if callbackContext then
                            DependencyStatus.markSuccess(callbackContext, name, 0)
                        end
                    end)
                end

                -- Return stale cached value immediately
                if cached.results and #cached.results > 0 then
                    return table.unpack(cached.results)
                end
                return nil
            end

            -- No cache or expired: blocking call to populate initial cache
            -- This only happens on the very first call per method
            if proxy._pending[key] then
                local waitDeadline = os.epoch("utc") + (timeout * 1000)
                while proxy._pending[key] and os.epoch("utc") < waitDeadline do
                    EventUtils.sleep(0.05)
                end
                local warmed = proxy._cache[key]
                if warmed and warmed.results then
                    if warmed.results and #warmed.results > 0 then
                        return table.unpack(warmed.results)
                    end
                    return nil
                end
            end

            proxy._pending[key] = true
            local startedAt = now
            local results, err = client:call(proxy._hostId, name, methodName, args, timeout)

            if err then
                proxy._pending[key] = nil
                proxy._failureCount = proxy._failureCount + 1
                proxy._lastFailureTime = os.epoch("utc")
                if proxy._failureCount >= MAX_CONSECUTIVE_FAILURES then
                    proxy._connected = false
                end
                -- Don't cache nil — let next render cycle retry immediately
                -- With the network drain fix, retries should succeed quickly
                if contextKey then
                    DependencyStatus.markError(contextKey, name, err)
                end
                return nil
            end

            proxy._failureCount = 0
            proxy._cache[key] = {
                results = results,
                timestamp = now
            }
            proxy._pending[key] = nil
            if contextKey then
                DependencyStatus.markSuccess(contextKey, name, os.epoch("utc") - startedAt)
            end

            if results and #results > 0 then
                return table.unpack(results)
            end
            return nil
        end
    end

    -- Clear all cached results (e.g., after reconnect)
    proxy.clearCache = function()
        proxy._cache = {}
        proxy._pending = {}
        proxy._nextRefreshAt = {}
    end

    -- Add peripheral-like helper methods
    proxy.isConnected = function()
        return proxy._connected
    end

    proxy.reconnect = function()
        proxy._reconnecting = true
        local found = client:rediscover(name)
        proxy._reconnecting = false

        if found then
            proxy._connected = true
            proxy._hostId = found.hostId
            proxy._failureCount = 0
            proxy.clearCache()
        end
        return proxy._connected
    end

    proxy.getType = function()
        return proxy._type
    end

    proxy.getName = function()
        return proxy._name
    end

    proxy.getMethods = function()
        return methods
    end

    return proxy
end

-- Check if an object is a remote proxy
function RemoteProxy.isProxy(obj)
    return type(obj) == "table" and obj._isRemote == true
end

return RemoteProxy
