local AEInterface = mpm('peripherals/AEInterface')
local EnergyInterface = mpm('peripherals/EnergyInterface')
local MachineActivity = mpm('peripherals/MachineActivity')

local Discovery = {}
Discovery.__index = Discovery

function Discovery.new()
    local self = setmetatable({}, Discovery)
    self._ae = nil
    self._aeCheckedAt = 0
    self._aeCheckIntervalMs = 10000
    return self
end

local function nowMs()
    return os.epoch("utc")
end

function Discovery:getAE()
    local now = nowMs()
    if self._ae and (now - self._aeCheckedAt) < self._aeCheckIntervalMs then
        return self._ae
    end

    self._aeCheckedAt = now
    local ok, exists = pcall(AEInterface.exists)
    if ok and exists then
        local okNew, instance = pcall(AEInterface.new)
        if okNew then
            self._ae = instance
            return self._ae
        end
    end

    self._ae = nil
    return nil
end

function Discovery:getEnergyStorages()
    return EnergyInterface.findAll()
end

function Discovery:getMachines()
    local types = MachineActivity.buildTypeList("all")
    local filtered = {}
    for _, entry in ipairs(types) do
        if entry.classification.mod == "mekanism" or entry.classification.mod == "mi" then
            table.insert(filtered, entry)
        end
    end
    return filtered
end

return Discovery
