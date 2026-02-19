-- EnergyInterface.lua
-- Unified energy storage discovery and monitoring across all mods
-- Uses CC:Tweaked's generic peripheral system (energy_storage type)

local Yield = mpm('utils/Yield')
local Text = mpm('utils/Text')
local Peripherals = mpm('utils/Peripherals')
local EnergySnapshotBus = mpm('peripherals/EnergySnapshotBus')

local EnergyInterface = {}

-- Known mod prefixes for classification
local MOD_PREFIXES = {
    ["mekanism"] = { label = "Mekanism", color = colors.cyan },
    ["powah"] = { label = "Powah", color = colors.purple },
    ["thermal"] = { label = "Thermal", color = colors.orange },
    ["immersiveengineering"] = { label = "IE", color = colors.brown },
    ["ae2"] = { label = "AE2", color = colors.lightBlue },
    ["appliedenergistics2"] = { label = "AE2", color = colors.lightBlue },
    ["modern_industrialization"] = { label = "MI", color = colors.blue },
    ["techreborn"] = { label = "TechReborn", color = colors.yellow },
    ["createaddition"] = { label = "Create", color = colors.lime },
    ["fluxnetworks"] = { label = "Flux", color = colors.magenta },
}

-- Energy storage type patterns (for more specific classification)
local STORAGE_PATTERNS = {
    { pattern = "energy_cube", label = "Energy Cube" },
    { pattern = "energycube", label = "Energy Cube" },
    { pattern = "battery", label = "Battery" },
    { pattern = "energy_cell", label = "Energy Cell" },
    { pattern = "energycell", label = "Energy Cell" },
    { pattern = "capacitor", label = "Capacitor" },
    { pattern = "accumulator", label = "Accumulator" },
    { pattern = "flux_storage", label = "Flux Storage" },
    { pattern = "fluxstorage", label = "Flux Storage" },
    { pattern = "induction", label = "Induction Matrix" },
}

local function hasEnergyMethods(p)
    if not p then return false end
    if type(p.getEnergy) ~= "function" then return false end
    if type(p.getEnergyCapacity) == "function" then return true end
    if type(p.getMaxEnergy) == "function" then return true end
    return false
end

local function isLikelyStorageType(typeName, peripheralName)
    local id = (typeName or peripheralName or ""):lower()
    for _, pattern in ipairs(STORAGE_PATTERNS) do
        if id:find(pattern.pattern) then
            return true
        end
    end
    return false
end

local function joulesToFE(value)
    if type(mekanismEnergyHelper) == "table" and type(mekanismEnergyHelper.joulesToFE) == "function" then
        local ok, converted = pcall(mekanismEnergyHelper.joulesToFE, value)
        if ok and type(converted) == "number" then
            return converted
        end
    end
    return value / 2.5
end

-- Check if energy_storage peripherals exist
function EnergyInterface.exists()
    local p = Peripherals.find("energy_storage") or Peripherals.find("energyStorage")
    return p ~= nil
end

-- Find all energy storage peripherals
-- Returns array of { peripheral, name, type }
function EnergyInterface.findAll()
    if EnergySnapshotBus and EnergySnapshotBus.isRunning and EnergySnapshotBus.isRunning() then
        local entries = EnergySnapshotBus.getEntries()
        if entries and #entries > 0 then
            local storages = {}
            for idx, entry in ipairs(entries) do
                table.insert(storages, {
                    peripheral = entry.peripheral,
                    name = entry.name,
                    primaryType = entry.primaryType or "energy_storage",
                    types = {entry.primaryType or "energy_storage"}
                })
                Yield.check(idx, 25)
            end
            return storages
        end
    end

    local storages = {}
    local names = Peripherals.getNames()

    for idx, name in ipairs(names) do
        local primaryType = Peripherals.getType(name)
        local hasEnergyStorageType = Peripherals.hasType(name, "energy_storage")
        local p = Peripherals.wrap(name)

        local isStorage = hasEnergyStorageType or isLikelyStorageType(primaryType, name)
        if isStorage and hasEnergyMethods(p) then
            table.insert(storages, {
                peripheral = p,
                name = name,
                primaryType = primaryType or (hasEnergyStorageType and "energy_storage" or "unknown_storage"),
                types = {primaryType or "energy_storage"}
            })
        end
        Yield.check(idx, 10)
    end

    return storages
end

-- Classify an energy storage peripheral
-- Returns { mod, modLabel, modColor, storageType, shortName }
function EnergyInterface.classify(name, primaryType)
    local result = {
        mod = "unknown",
        modLabel = "Other",
        modColor = colors.lightGray,
        storageType = "Storage",
        shortName = name
    }

    -- Extract mod from peripheral type or name
    local modPrefix = primaryType and primaryType:match("^([^:]+):") or name:match("^([^:]+):")

    if modPrefix and MOD_PREFIXES[modPrefix] then
        result.mod = modPrefix
        result.modLabel = MOD_PREFIXES[modPrefix].label
        result.modColor = MOD_PREFIXES[modPrefix].color
    end

    -- Determine storage type from name/type
    local lowerName = (primaryType or name):lower()
    for _, pattern in ipairs(STORAGE_PATTERNS) do
        if lowerName:find(pattern.pattern) then
            result.storageType = pattern.label
            break
        end
    end

    -- Generate short name
    result.shortName = name:match("_(%d+)$") or name:match(":(.+)$") or name
    if #result.shortName > 12 then
        result.shortName = result.shortName:sub(1, 11) .. "."
    end

    return result
end

-- Get energy status from a peripheral (normalized)
-- Uses CC:Tweaked generic methods (FE) with fallback to Mekanism methods (Joules)
-- Returns nil if peripheral is unreachable (remote timeout, etc.)
function EnergyInterface.getStatus(p)
    if not p then return nil end

    if EnergySnapshotBus and EnergySnapshotBus.isRunning and EnergySnapshotBus.isRunning() then
        local snap = EnergySnapshotBus.getStatusByPeripheral(p)
        if snap and snap.ok and type(snap.data) == "table" then
            return snap.data
        end
    end

    local status = {
        stored = 0,
        capacity = 0,
        percent = 0,
        unit = "FE",
        storedFE = 0,
        capacityFE = 0
    }

    -- Try CC:Tweaked generic methods first (FE)
    local storedOk, stored = pcall(p.getEnergy)
    local capacityOk, capacity = pcall(p.getEnergyCapacity)

    if storedOk and capacityOk and type(stored) == "number" and type(capacity) == "number" then
        status.stored = stored
        status.capacity = capacity > 0 and capacity or 1
        status.percent = status.capacity > 0 and (status.stored / status.capacity) or 0
        status.storedFE = status.stored
        status.capacityFE = status.capacity
        return status
    end

    -- Fallback to Mekanism methods (Joules)
    storedOk, stored = pcall(p.getEnergy)  -- Mekanism also uses getEnergy
    local maxOk, max = pcall(p.getMaxEnergy)

    if storedOk and maxOk and type(stored) == "number" and type(max) == "number" then
        status.stored = stored
        status.capacity = max > 0 and max or 1
        status.percent = status.capacity > 0 and (status.stored / status.capacity) or 0
        status.unit = "J"
        status.storedFE = joulesToFE(status.stored)
        status.capacityFE = joulesToFE(status.capacity)
        return status
    end

    -- Peripheral unreachable or returned non-numeric data
    return nil
end

-- Discover all energy storage grouped by mod
-- Returns { [mod] = { label, color, storages = { ... } } }
function EnergyInterface.discoverByMod()
    local all = EnergyInterface.findAll()
    local groups = {}

    for idx, storage in ipairs(all) do
        local classification = EnergyInterface.classify(storage.name, storage.primaryType)
        local mod = classification.mod

        if not groups[mod] then
            groups[mod] = {
                label = classification.modLabel,
                color = classification.modColor,
                storages = {}
            }
        end

        local status = EnergyInterface.getStatus(storage.peripheral)

        -- Skip peripherals that returned nil status (unreachable remote, etc.)
        if status then
            table.insert(groups[mod].storages, {
                peripheral = storage.peripheral,
                name = storage.name,
                shortName = classification.shortName,
                storageType = classification.storageType,
                status = status
            })
        end

        Yield.check(idx, 5)
    end

    return groups
end

-- Get total energy across all storages
function EnergyInterface.getTotals()
    local all = EnergyInterface.findAll()
    local totals = {
        stored = 0,
        capacity = 0,
        count = 0,
        unit = "FE"
    }

    for idx, storage in ipairs(all) do
        local status = EnergyInterface.getStatus(storage.peripheral)
        if status then
            totals.stored = totals.stored + (status.storedFE or status.stored or 0)
            totals.capacity = totals.capacity + (status.capacityFE or status.capacity or 0)
            totals.count = totals.count + 1
        end
        Yield.check(idx, 10)
    end

    totals.percent = totals.capacity > 0 and (totals.stored / totals.capacity) or 0
    return totals
end

-- Filter storages by name pattern
-- pattern: string to match against peripheral name (supports * as wildcard)
function EnergyInterface.filterByName(storages, pattern)
    if not pattern or pattern == "" or pattern == "*" then
        return storages
    end

    -- Convert simple wildcard to Lua pattern
    local luaPattern = pattern:gsub("%*", ".*"):gsub("%?", ".")

    local filtered = {}
    for _, storage in ipairs(storages) do
        if storage.name:match(luaPattern) then
            table.insert(filtered, storage)
        end
    end

    return filtered
end

-- Get available filter options (for config)
function EnergyInterface.getModFilterOptions()
    local groups = EnergyInterface.discoverByMod()
    local options = {{ value = "all", label = "All Mods" }}

    for mod, data in pairs(groups) do
        if #data.storages > 0 then
            table.insert(options, {
                value = mod,
                label = data.label .. " (" .. #data.storages .. ")"
            })
        end
    end

    return options
end

-- Format energy value for display (delegates to Text.formatEnergy)
function EnergyInterface.formatEnergy(value, unit)
    return Text.formatEnergy(value, unit)
end

return EnergyInterface
