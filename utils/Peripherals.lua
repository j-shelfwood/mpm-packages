-- Peripherals.lua
-- Centralized peripheral access module
-- Loads RemotePeripheral for network-transparent access, falls back to raw peripheral API
-- All views and adapters should import this instead of using peripheral.* directly

local Peripherals = {}
local _remote = nil
local _loaded = false

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

-- Standard peripheral API delegation
function Peripherals.find(pType, filter) return getAPI().find(pType, filter) end
function Peripherals.getNames() return getAPI().getNames() end
function Peripherals.wrap(name) return getAPI().wrap(name) end
function Peripherals.getType(name) return getAPI().getType(name) end
function Peripherals.isPresent(name) return getAPI().isPresent(name) end
function Peripherals.hasType(name, t) return getAPI().hasType(name, t) end
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
