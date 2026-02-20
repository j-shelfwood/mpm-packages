-- RemotePeripheral.lua
-- Drop-in replacement for peripheral API that includes remote peripherals
-- Use this instead of peripheral.find/wrap to transparently access remote peripherals

local RemoteProxy = mpm('net/RemoteProxy')

local RemotePeripheral = {}

local function normalizeTypeToken(typeName)
    if type(typeName) ~= "string" or typeName == "" then
        return nil
    end
    return typeName:lower():gsub("[^%w]", "")
end

local function typeMatches(actual, expected)
    local a = normalizeTypeToken(actual)
    local b = normalizeTypeToken(expected)
    if not a or not b then
        return false
    end
    if a == b then
        return true
    end

    local suffixA = tostring(actual):match(":(.+)$")
    local suffixB = tostring(expected):match(":(.+)$")
    local sa = normalizeTypeToken(suffixA)
    local sb = normalizeTypeToken(suffixB)

    return (sa and sa == b) or (a == sb) or (sa and sb and sa == sb) or false
end

-- Client instance stored in _G for truly global state
-- This ensures setClient() in one module is visible to all others
-- even if mpm() doesn't cache modules properly
_G._shelfos_peripheralClient = _G._shelfos_peripheralClient  -- preserve existing

-- Set the peripheral client instance
-- @param c PeripheralClient instance
function RemotePeripheral.setClient(c)
    _G._shelfos_peripheralClient = c
end

-- Get the peripheral client instance
function RemotePeripheral.getClient()
    return _G._shelfos_peripheralClient
end

-- Check if client is available
function RemotePeripheral.hasClient()
    return _G._shelfos_peripheralClient ~= nil
end

-- Find a peripheral by type (checks local first, then remote)
-- @param pType Peripheral type to find
-- @param filter Optional filter function(name, peripheral) -> boolean
-- @return peripheral or nil (can return multiple if no filter)
function RemotePeripheral.find(pType, filter)
    -- Try local first
    local locals = {peripheral.find(pType, filter)}
    if #locals > 0 then
        return table.unpack(locals)
    end

    -- Try remote
    local client = _G._shelfos_peripheralClient
    if client then
        local remote = client:find(pType)
        if remote then
            -- Apply filter if provided
            if filter then
                if filter(remote._name, remote) then
                    return remote
                end
            else
                return remote
            end
        end
    end

    return nil
end

-- Find all peripherals by type (local + remote)
-- @param pType Peripheral type to find
-- @return Array of peripherals
function RemotePeripheral.findAll(pType)
    local results = {}

    -- Get locals
    local locals = {peripheral.find(pType)}
    for _, p in ipairs(locals) do
        table.insert(results, p)
    end

    -- Get remotes
    local client = _G._shelfos_peripheralClient
    if client then
        local remotes = client:findAll(pType)
        for _, p in ipairs(remotes) do
            table.insert(results, p)
        end
    end

    return results
end

-- Wrap a peripheral by name (checks local first, then remote)
-- @param name Peripheral name
-- @return peripheral or nil
function RemotePeripheral.wrap(name)
    -- Try local first
    local p = peripheral.wrap(name)
    if p then
        return p
    end

    -- Try remote
    local client = _G._shelfos_peripheralClient
    if client then
        return client:wrap(name)
    end

    return nil
end

-- Get all peripheral names (local + remote)
-- @return Array of names
function RemotePeripheral.getNames()
    local names = {}
    local seen = {}

    for _, name in ipairs(peripheral.getNames()) do
        if not seen[name] then
            table.insert(names, name)
            seen[name] = true
        end
    end

    local client = _G._shelfos_peripheralClient
    if client then
        local remoteNames = client:getNames()
        for _, name in ipairs(remoteNames) do
            if not seen[name] then
                table.insert(names, name)
                seen[name] = true
            end
        end
    end

    return names
end

-- Check if a peripheral is present (local or remote)
-- @param name Peripheral name
-- @return boolean
function RemotePeripheral.isPresent(name)
    if peripheral.isPresent(name) then
        return true
    end

    local client = _G._shelfos_peripheralClient
    if client then
        return client:isPresent(name)
    end

    return false
end

-- Get the type of a peripheral (local or remote)
-- @param name Peripheral name or wrapped peripheral
-- @return type string or nil
function RemotePeripheral.getType(name)
    -- Handle wrapped peripheral
    if type(name) == "table" then
        if RemoteProxy.isProxy(name) then
            return name._type
        end
        return peripheral.getType(name)
    end

    -- Try local
    local pType = peripheral.getType(name)
    if pType then
        return pType
    end

    -- Try remote
    local client = _G._shelfos_peripheralClient
    if client then
        return client:getType(name)
    end

    return nil
end

-- Check if peripheral has a specific type (local or remote)
-- @param name Peripheral name or wrapped peripheral
-- @param pType Type to check
-- @return boolean or nil
function RemotePeripheral.hasType(name, pType)
    -- Handle wrapped peripheral
    if type(name) == "table" then
        if RemoteProxy.isProxy(name) then
            return typeMatches(name._type, pType)
        end
        return peripheral.hasType(name, pType)
    end

    local client = _G._shelfos_peripheralClient
    local localPresent = peripheral.isPresent(name)

    -- Local-first when matching, but do not let local false mask valid remote type.
    if localPresent and peripheral.hasType(name, pType) then
        return true
    end

    -- Try remote even when local is present but not matching.
    if client then
        local remoteMatch = client:hasType(name, pType)
        if remoteMatch ~= nil then
            return remoteMatch
        end
    end

    if localPresent then
        return false
    end
    return nil
end

-- Get methods of a peripheral (local or remote)
-- @param name Peripheral name
-- @return Array of method names or nil
function RemotePeripheral.getMethods(name)
    -- Try local
    local methods = peripheral.getMethods(name)
    if methods then
        return methods
    end

    -- Try remote
    local client = _G._shelfos_peripheralClient
    if client then
        return client:getMethods(name)
    end

    return nil
end

-- Call a method on a peripheral (local or remote)
-- @param name Peripheral name
-- @param method Method name
-- @param ... Arguments
-- @return Method results
function RemotePeripheral.call(name, method, ...)
    -- Check if local
    if peripheral.isPresent(name) then
        return peripheral.call(name, method, ...)
    end

    -- Try remote
    local client = _G._shelfos_peripheralClient
    if client then
        local info = client:resolveInfo(name)
        if info then
            local args = {...}
            local results, err = client:call(info.hostId, info.name, method, args)
            if results then
                return table.unpack(results)
            end
        end
    end

    return nil
end

-- Get user-friendly name for local or remote peripheral identifier
-- @param name Peripheral name/key
-- @return display string
function RemotePeripheral.getDisplayName(name)
    local client = _G._shelfos_peripheralClient
    if client then
        local displayName = client:getDisplayName(name)
        if displayName then
            return displayName
        end
    end
    return name
end

-- Check if a peripheral object is a remote proxy
-- @param p Peripheral object
-- @return boolean
function RemotePeripheral.isRemote(p)
    return RemoteProxy.isProxy(p)
end

-- Discover remote peripherals
-- @param timeout Seconds to wait
-- @return Number of remote peripherals found
function RemotePeripheral.discover(timeout)
    local client = _G._shelfos_peripheralClient
    if client then
        return client:discover(timeout)
    end
    return 0
end

return RemotePeripheral
