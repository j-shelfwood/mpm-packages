-- EnergyInterface.lua
-- Unified energy storage discovery and monitoring across all mods
-- Uses CC:Tweaked's generic peripheral system (energy_storage type)

local Yield = mpm('utils/Yield')
local Peripherals = mpm('utils/Peripherals')

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
    { pattern = "battery", label = "Battery" },
    { pattern = "energy_cell", label = "Energy Cell" },
    { pattern = "capacitor", label = "Capacitor" },
    { pattern = "accumulator", label = "Accumulator" },
    { pattern = "flux_storage", label = "Flux Storage" },
    { pattern = "induction", label = "Induction Matrix" },
}

-- Check if energy_storage peripherals exist
function EnergyInterface.exists()
    local p = Peripherals.find("energy_storage")
    return p ~= nil
end

-- Find all energy storage peripherals
-- Returns array of { peripheral, name, type }
function EnergyInterface.findAll()
    local storages = {}
    local names = Peripherals.getNames()

    for idx, name in ipairs(names) do
        local types = {Peripherals.getType(name)}

        -- Check if this peripheral has energy_storage as one of its types
        for _, pType in ipairs(types) do
            if pType == "energy_storage" then
                local p = Peripherals.wrap(name)
                if p and p.getEnergy and p.getEnergyCapacity then
                    -- Get primary type (first non-energy_storage type)
                    local primaryType = nil
                    for _, t in ipairs(types) do
                        if t ~= "energy_storage" then
                            primaryType = t
                            break
                        end
                    end

                    table.insert(storages, {
                        peripheral = p,
                        name = name,
                        primaryType = primaryType or "energy_storage",
                        types = types
                    })
                end
                break
            end
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
function EnergyInterface.getStatus(p)
    local status = {
        stored = 0,
        capacity = 0,
        percent = 0,
        unit = "FE"
    }

    -- Try CC:Tweaked generic methods first (FE)
    local storedOk, stored = pcall(p.getEnergy)
    local capacityOk, capacity = pcall(p.getEnergyCapacity)

    if storedOk and capacityOk then
        status.stored = stored or 0
        status.capacity = capacity or 1
        status.percent = status.capacity > 0 and (status.stored / status.capacity) or 0
        return status
    end

    -- Fallback to Mekanism methods (Joules)
    storedOk, stored = pcall(p.getEnergy)  -- Mekanism also uses getEnergy
    local maxOk, max = pcall(p.getMaxEnergy)

    if storedOk and maxOk then
        status.stored = stored or 0
        status.capacity = max or 1
        status.percent = status.capacity > 0 and (status.stored / status.capacity) or 0
        status.unit = "J"
        return status
    end

    return status
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

        table.insert(groups[mod].storages, {
            peripheral = storage.peripheral,
            name = storage.name,
            shortName = classification.shortName,
            storageType = classification.storageType,
            status = status
        })

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
        count = 0
    }

    for idx, storage in ipairs(all) do
        local status = EnergyInterface.getStatus(storage.peripheral)
        totals.stored = totals.stored + status.stored
        totals.capacity = totals.capacity + status.capacity
        totals.count = totals.count + 1
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
        table.insert(options, {
            value = mod,
            label = data.label .. " (" .. #data.storages .. ")"
        })
    end

    return options
end

-- Format energy value for display
function EnergyInterface.formatEnergy(value, unit)
    unit = unit or "FE"
    if value >= 1e12 then
        return string.format("%.2fT%s", value / 1e12, unit)
    elseif value >= 1e9 then
        return string.format("%.2fG%s", value / 1e9, unit)
    elseif value >= 1e6 then
        return string.format("%.2fM%s", value / 1e6, unit)
    elseif value >= 1e3 then
        return string.format("%.1fk%s", value / 1e3, unit)
    else
        return string.format("%.0f%s", value, unit)
    end
end

return EnergyInterface
