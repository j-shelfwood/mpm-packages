-- RemoteProxy.lua
-- Creates a proxy object that looks like a real peripheral
-- but forwards method calls over the network
-- Includes auto-reconnect with backoff for resilient remote access

local Protocol = mpm('net/Protocol')

local RemoteProxy = {}

-- Reconnection settings
local MAX_CONSECUTIVE_FAILURES = 3   -- Disconnect after this many consecutive failures
local RECONNECT_COOLDOWN_MS = 10000  -- Wait 10 seconds before auto-reconnect attempt
local RECONNECT_TIMEOUT = 3          -- Seconds for reconnect discovery

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

    -- Auto-reconnect if disconnected and cooldown has elapsed
    -- @return true if reconnected or already connected
    local function ensureConnected()
        if proxy._connected then
            return true
        end

        -- Check cooldown
        local now = os.epoch("utc")
        if now - proxy._lastFailureTime < RECONNECT_COOLDOWN_MS then
            return false
        end

        -- Prevent re-entrant reconnect attempts
        if proxy._reconnecting then
            return false
        end

        -- Attempt reconnect
        proxy._reconnecting = true
        local found = client:rediscover(name)
        proxy._reconnecting = false

        if found then
            proxy._connected = true
            proxy._hostId = found.hostId
            proxy._failureCount = 0
            return true
        end

        -- Reset timer so we don't spam reconnect attempts
        proxy._lastFailureTime = now
        return false
    end

    -- Generate method stubs for each available method
    for _, methodName in ipairs(methods) do
        proxy[methodName] = function(...)
            -- Auto-reconnect if disconnected
            if not ensureConnected() then
                return nil
            end

            -- Pack arguments
            local args = {...}

            -- Call via client
            local results, err = client:call(hostId, name, methodName, args)

            if err then
                proxy._failureCount = proxy._failureCount + 1
                proxy._lastFailureTime = os.epoch("utc")

                -- Only disconnect after consecutive failures exceed threshold
                if proxy._failureCount >= MAX_CONSECUTIVE_FAILURES then
                    proxy._connected = false
                end
                return nil
            end

            -- Success: reset failure counter
            proxy._failureCount = 0

            -- Unpack results
            if results and #results > 0 then
                return table.unpack(results)
            end

            return nil
        end
    end

    -- Add peripheral-like helper methods
    proxy.isConnected = function()
        return proxy._connected
    end

    proxy.reconnect = function()
        -- Force reconnect attempt (ignores cooldown)
        proxy._reconnecting = true
        local found = client:rediscover(name)
        proxy._reconnecting = false

        if found then
            proxy._connected = true
            proxy._hostId = found.hostId
            proxy._failureCount = 0
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
