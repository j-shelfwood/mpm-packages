-- Peripherals.lua
-- Centralized peripheral access module
-- Loads RemotePeripheral for network-transparent access, falls back to raw peripheral API
-- All views and adapters should import this instead of using peripheral.* directly

local Peripherals = {}
local _remote = nil
local _loaded = false

local TYPE_ALIASES = {
    energy_storage = { "energy_storage", "energyStorage" },
    energyStorage = { "energy_storage", "energyStorage" },
    energy_detector = { "energy_detector", "energyDetector" },
    environment_detector = { "environment_detector", "environmentDetector" },
    player_detector = { "player_detector", "playerDetector" },
    fluid_storage = { "fluid_storage", "fluidStorage" },
    me_bridge = { "me_bridge", "meBridge" },
    rsBridge = { "rsBridge", "rs_bridge" }
}

local function getAPI()
    if not _loaded then
        local ok, Remote = pcall(mpm, 'net/RemotePeripheral')
        if ok and Remote then
            _remote = Remote
        end
        _loaded = true
    end
    return _remote or peripheral
end

local function normalizeTypeToken(typeName)
    if type(typeName) ~= "string" or typeName == "" then
        return nil
    end
    return typeName:lower():gsub("[^%w]", "")
end

local function buildTypeCandidates(typeName)
    local out = {}
    local seen = {}

    local function push(value)
        local token = normalizeTypeToken(value)
        if token and not seen[token] then
            seen[token] = true
            table.insert(out, token)
        end
    end

    push(typeName)
    if type(typeName) == "string" then
        local suffix = typeName:match(":(.+)$")
        if suffix then
            push(suffix)
        end
    end

    local aliases = TYPE_ALIASES[typeName]
    if aliases then
        for _, alias in ipairs(aliases) do
            push(alias)
            local aliasSuffix = alias:match(":(.+)$")
            if aliasSuffix then
                push(aliasSuffix)
            end
        end
    end

    return out
end

function Peripherals.typeMatches(actualType, expectedType)
    if not actualType or not expectedType then
        return false
    end

    local actualCandidates = buildTypeCandidates(actualType)
    local expectedCandidates = buildTypeCandidates(expectedType)
    local expectedSet = {}

    for _, token in ipairs(expectedCandidates) do
        expectedSet[token] = true
    end

    for _, token in ipairs(actualCandidates) do
        if expectedSet[token] then
            return true
        end
    end

    return false
end

-- Standard peripheral API delegation
function Peripherals.find(pType, filter)
    local api = getAPI()
    local direct = {api.find(pType, filter)}
    if #direct > 0 then
        return table.unpack(direct)
    end

    local matches = {}
    for _, name in ipairs(Peripherals.getNames()) do
        if Peripherals.hasType(name, pType) then
            local wrapped = Peripherals.wrap(name)
            local include = true
            if filter then
                include = filter(name, wrapped)
            end
            if include then
                table.insert(matches, wrapped)
            end
        end
    end

    if #matches > 0 then
        return table.unpack(matches)
    end
    return nil
end
function Peripherals.getNames() return getAPI().getNames() end
function Peripherals.wrap(name) return getAPI().wrap(name) end
function Peripherals.getType(name) return getAPI().getType(name) end
function Peripherals.isPresent(name) return getAPI().isPresent(name) end
function Peripherals.hasType(name, t)
    local api = getAPI()
    local direct = api.hasType(name, t)
    if direct == true then
        return true
    end

    local actual = api.getType(name)
    if Peripherals.typeMatches(actual, t) then
        return true
    end

    if direct ~= nil then
        return direct
    end
    return nil
end
function Peripherals.getMethods(name) return getAPI().getMethods(name) end
function Peripherals.call(name, ...) return getAPI().call(name, ...) end
function Peripherals.getDisplayName(name)
    local api = getAPI()
    if api.getDisplayName then
        return api.getDisplayName(name)
    end
    return name
end

-- getName: handles both local peripherals and RemoteProxy objects
function Peripherals.getName(p)
    if type(p) == "table" and p._name then return p._name end
    return peripheral.getName(p)
end

-- Force re-check of RemotePeripheral availability
function Peripherals.refresh()
    _loaded = false
end

return Peripherals
