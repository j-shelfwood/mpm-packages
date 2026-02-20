local RemoteProxy = mpm('net/RemoteProxy')

local PeripheralRegistry = {}

local function makeRemoteKey(hostId, name)
    return tostring(hostId) .. "::" .. tostring(name)
end

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

local function sortRemoteKeys(keys, remotePeripherals)
    table.sort(keys, function(a, b)
        local ai = remotePeripherals[a]
        local bi = remotePeripherals[b]
        if not ai then return false end
        if not bi then return true end
        local ah = tonumber(ai.hostId) or math.huge
        local bh = tonumber(bi.hostId) or math.huge
        if ah ~= bh then
            return ah < bh
        end
        return tostring(a) < tostring(b)
    end)
end

local function sortedRemoteKeys(remotePeripherals)
    local keys = {}
    for key in pairs(remotePeripherals) do
        table.insert(keys, key)
    end
    sortRemoteKeys(keys, remotePeripherals)
    return keys
end

function PeripheralRegistry.init(client)
    client.remotePeripherals = {}
    client.remoteByName = {}
    client.remoteNameAlias = {}
    client.hostPeripheralKeys = {}
    client.hostComputers = {}
    client.hostStateHashes = {}
end

function PeripheralRegistry.rebuildNameIndexes(client)
    client.remoteByName = {}
    client.remoteNameAlias = {}

    for key, info in pairs(client.remotePeripherals) do
        local name = info.name
        if name and name ~= "" then
            client.remoteByName[name] = client.remoteByName[name] or {}
            table.insert(client.remoteByName[name], key)
        end
    end

    for name, keys in pairs(client.remoteByName) do
        sortRemoteKeys(keys, client.remotePeripherals)
        client.remoteNameAlias[name] = keys[1]
    end
end

function PeripheralRegistry.removeHostRemotes(client, hostId)
    local keys = client.hostPeripheralKeys[hostId]
    if not keys then
        return
    end

    for key in pairs(keys) do
        client.remotePeripherals[key] = nil
    end
    client.hostPeripheralKeys[hostId] = nil
    PeripheralRegistry.rebuildNameIndexes(client)
end

function PeripheralRegistry.registerRemote(client, hostId, name, pType, methods, _, deferIndexRebuild)
    local key = makeRemoteKey(hostId, name)
    local hostComputer = client.hostComputers[hostId]
    local hostComputerName = hostComputer and hostComputer.computerName or nil
    local displayName = hostComputerName and (name .. " @ " .. hostComputerName) or (name .. " @ #" .. tostring(hostId))

    local proxy = RemoteProxy.create(client, hostId, name, pType, methods, key, displayName)

    client.remotePeripherals[key] = {
        key = key,
        name = name,
        displayName = displayName,
        hostId = hostId,
        hostComputerName = hostComputerName,
        type = pType,
        methods = methods,
        proxy = proxy
    }

    client.hostPeripheralKeys[hostId] = client.hostPeripheralKeys[hostId] or {}
    client.hostPeripheralKeys[hostId][key] = true
    if not deferIndexRebuild then
        PeripheralRegistry.rebuildNameIndexes(client)
    end
end

function PeripheralRegistry.resolveInfo(client, nameOrKey)
    if not nameOrKey then
        return nil
    end

    local info = client.remotePeripherals[nameOrKey]
    if info then
        return info
    end

    local aliasKey = client.remoteNameAlias[nameOrKey]
    if aliasKey then
        return client.remotePeripherals[aliasKey]
    end

    return nil
end

function PeripheralRegistry.getDisplayName(client, nameOrKey)
    local info = PeripheralRegistry.resolveInfo(client, nameOrKey)
    if not info then
        return nil
    end
    return info.displayName or info.key or info.name
end

function PeripheralRegistry.getCount(client)
    local count = 0
    for _ in pairs(client.remotePeripherals) do
        count = count + 1
    end
    return count
end

function PeripheralRegistry.find(client, pType)
    for _, key in ipairs(sortedRemoteKeys(client.remotePeripherals)) do
        local info = client.remotePeripherals[key]
        if typeMatches(info.type, pType) then
            return info.proxy
        end
    end
    return nil
end

function PeripheralRegistry.findAll(client, pType)
    local results = {}
    for _, key in ipairs(sortedRemoteKeys(client.remotePeripherals)) do
        local info = client.remotePeripherals[key]
        if typeMatches(info.type, pType) then
            table.insert(results, info.proxy)
        end
    end
    return results
end

function PeripheralRegistry.wrap(client, name)
    local info = PeripheralRegistry.resolveInfo(client, name)
    if info then
        return info.proxy
    end
    return nil
end

function PeripheralRegistry.getNames(client)
    local names = {}
    local nameIndex = {}

    for rawName, keys in pairs(client.remoteByName) do
        if #keys == 1 then
            nameIndex[rawName] = true
        else
            for _, key in ipairs(keys) do
                nameIndex[key] = true
            end
        end
    end

    for name in pairs(nameIndex) do
        table.insert(names, name)
    end

    table.sort(names)
    return names
end

function PeripheralRegistry.getType(client, name)
    local info = PeripheralRegistry.resolveInfo(client, name)
    if info then
        return info.type
    end
    return nil
end

function PeripheralRegistry.hasType(client, name, pType)
    local info = PeripheralRegistry.resolveInfo(client, name)
    if info then
        return typeMatches(info.type, pType)
    end
    return nil
end

function PeripheralRegistry.getMethods(client, name)
    local info = PeripheralRegistry.resolveInfo(client, name)
    if info then
        return info.methods
    end
    return nil
end

function PeripheralRegistry.isPresent(client, name)
    return PeripheralRegistry.resolveInfo(client, name) ~= nil
end

function PeripheralRegistry.clear(client)
    client.remotePeripherals = {}
    client.remoteByName = {}
    client.remoteNameAlias = {}
    client.hostPeripheralKeys = {}
    client.hostComputers = {}
    client.hostStateHashes = {}
end

return PeripheralRegistry
