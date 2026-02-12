-- RemoteProxy.lua
-- Creates a proxy object that looks like a real peripheral
-- but forwards method calls over the network

local Protocol = mpm('net/Protocol')

local RemoteProxy = {}

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

    -- Generate method stubs for each available method
    for _, methodName in ipairs(methods) do
        proxy[methodName] = function(...)
            if not proxy._connected then
                return nil
            end

            -- Pack arguments
            local args = {...}

            -- Call via client
            local results, err = client:call(hostId, name, methodName, args)

            if err then
                -- Connection issue - mark as disconnected
                if err == "timeout" or err == "not_connected" then
                    proxy._connected = false
                end
                return nil
            end

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
        -- Try to rediscover this peripheral
        local found = client:rediscover(name)
        if found then
            proxy._connected = true
            proxy._hostId = found.hostId
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
