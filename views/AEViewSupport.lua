-- AEViewSupport.lua
-- Shared lifecycle helpers for AE-backed views/factories

local AEInterface = mpm("peripherals/" .. "AEInterface")

local AEViewSupport = {}
local capabilityCache = nil
local capabilityCacheAt = 0
local CAPABILITY_TTL_MS = 2000

local function nowMs()
    return os.epoch("utc")
end

local function copyTable(t)
    local out = {}
    for k, v in pairs(t or {}) do
        out[k] = v
    end
    return out
end

function AEViewSupport.invalidateCapabilities()
    capabilityCache = nil
    capabilityCacheAt = 0
end

function AEViewSupport.getCapabilities(forceRefresh)
    local now = nowMs()
    if not forceRefresh and capabilityCache and (now - capabilityCacheAt) < CAPABILITY_TTL_MS then
        return copyTable(capabilityCache)
    end

    local caps = {
        hasAE = false,
        hasChemical = false,
        bridge = nil,
    }

    if AEInterface and type(AEInterface.exists) == "function" then
        local ok, exists, bridge = pcall(AEInterface.exists)
        if ok and exists then
            caps.hasAE = true
            caps.bridge = bridge
            caps.hasChemical = bridge ~= nil and type(bridge.getChemicals) == "function"
        end
    end

    capabilityCache = caps
    capabilityCacheAt = now
    return copyTable(caps)
end

function AEViewSupport.mount(mountCheck)
    local caps = AEViewSupport.getCapabilities()
    if mountCheck then
        local ok, result = pcall(mountCheck, caps)
        return ok and result == true
    end
    return caps.hasAE == true
end

function AEViewSupport.init(self)
    if not AEInterface or type(AEInterface.new) ~= "function" then
        self.interface = nil
        return nil
    end
    local ok, interface = pcall(AEInterface.new)
    self.interface = ok and interface or nil
    return self.interface
end

function AEViewSupport.ensureInterface(self)
    if self.interface then
        return true, self.interface
    end

    local interface = AEViewSupport.init(self)
    if interface then
        return true, interface
    end

    return false, nil
end

function AEViewSupport.readStatus(self, key)
    if not self or not self.interface or type(self.interface.getReadStatus) ~= "function" then
        return { key = key, state = "unknown" }
    end

    local ok, status = pcall(self.interface.getReadStatus, self.interface, key)
    if not ok or type(status) ~= "table" then
        return { key = key, state = "unknown" }
    end
    return status
end

-- buildListener is retained for API compatibility but the snapshot bus has been removed.
-- Views now poll directly in getData() on a timer. listenEvents is empty; onEvent never fires.
function AEViewSupport.buildListener(_keys)
    return {}, function(_self, _eventName, _bridgeName, _key)
        return false
    end
end

return AEViewSupport
