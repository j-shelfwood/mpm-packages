local AEInterface = mpm('peripherals/AEInterface')
local EnergyInterface = mpm('peripherals/EnergyInterface')
local MachineActivity = mpm('peripherals/MachineActivity')
local Peripherals = mpm('utils/Peripherals')

local Discovery = {}
Discovery.__index = Discovery

local CACHE_TTL_MS = 30000  -- 30s TTL for peripheral scan results

function Discovery.new()
    local self = setmetatable({}, Discovery)
    self._ae = nil
    self._aeCheckedAt = 0
    self._aeCheckIntervalMs = 10000
    self._energyStorages = nil
    self._energyStoragesAt = 0
    self._machines = nil
    self._machinesAt = 0
    self._detectors = nil
    self._detectorsAt = 0
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
    local now = nowMs()
    if self._energyStorages and (now - self._energyStoragesAt) < CACHE_TTL_MS then
        return self._energyStorages
    end
    self._energyStoragesAt = now
    self._energyStorages = EnergyInterface.findAll()
    return self._energyStorages
end

function Discovery:getMachines()
    local now = nowMs()
    if self._machines and (now - self._machinesAt) < CACHE_TTL_MS then
        return self._machines
    end
    self._machinesAt = now
    local types = MachineActivity.buildTypeList("all")
    local filtered = {}
    for _, entry in ipairs(types) do
        if entry.classification.mod == "mekanism" or entry.classification.mod == "mi" then
            table.insert(filtered, entry)
        end
    end
    self._machines = filtered
    return self._machines
end

function Discovery:getEnergyDetectors()
    local now = nowMs()
    if self._detectors and (now - self._detectorsAt) < CACHE_TTL_MS then
        return self._detectors
    end
    self._detectorsAt = now
    local detectors = {}
    local names = Peripherals.getNames()
    for _, name in ipairs(names) do
        if Peripherals.hasType(name, "energy_detector") then
            local ok, wrapped = pcall(Peripherals.wrap, name)
            if ok and wrapped then
                table.insert(detectors, {
                    peripheral = wrapped,
                    name = name
                })
            end
        end
    end
    self._detectors = detectors
    return self._detectors
end

return Discovery
