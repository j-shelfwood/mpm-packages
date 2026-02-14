-- MachineActivity.lua
-- Unified machine activity detection across mods (MI, Mekanism, etc.)

local Yield = mpm('utils/Yield')

local MachineActivity = {}

-- Activity detection strategies by method availability
local ACTIVITY_STRATEGIES = {
    -- Modern Industrialization / Generic
    { method = "isBusy", detect = function(p) return p.isBusy() end },

    -- Mekanism Processing (recipe progress)
    {
        method = "getRecipeProgress",
        detect = function(p)
            local progress = p.getRecipeProgress()
            local total = p.getTicksRequired and p.getTicksRequired() or 0
            return progress > 0 and total > 0, {
                progress = progress,
                total = total,
                percent = total > 0 and (progress / total * 100) or 0
            }
        end
    },

    -- Mekanism Generators (production rate)
    {
        method = "getProductionRate",
        detect = function(p)
            local rate = p.getProductionRate()
            return rate > 0, { rate = rate }
        end
    },

    -- Mekanism Multiblocks (formed + type-specific)
    {
        method = "isFormed",
        detect = function(p)
            local formed = p.isFormed()
            if not formed then return false, { formed = false } end

            -- Check type-specific activity
            if p.getBoilRate then
                local rate = p.getBoilRate()
                return rate > 0, { formed = true, rate = rate }
            elseif p.getStatus then
                local status = p.getStatus()
                return status == true, { formed = true, status = status }
            elseif p.isIgnited then
                local ignited = p.isIgnited()
                return ignited, { formed = true, ignited = ignited }
            end

            return formed, { formed = true }
        end
    }
}

-- Mekanism category definitions
local MEKANISM_CATEGORIES = {
    processing = {
        label = "Processing",
        color = colors.cyan,
        types = {
            "enrichmentChamber", "crusher", "combiner", "metallurgicInfuser",
            "energizedSmelter", "precisionSawmill", "chemicalCrystallizer",
            "chemicalDissolutionChamber", "chemicalInfuser", "chemicalOxidizer",
            "chemicalWasher", "rotaryCondensentrator", "pressurizedReactionChamber",
            "electrolyticSeparator", "isotopicCentrifuge", "pigmentExtractor",
            "pigmentMixer", "paintingMachine", "nutritionalLiquifier",
            "antiprotonicNucleosynthesizer", "solarNeutronActivator",
            -- Factories (all tiers)
            "basicEnrichingFactory", "advancedEnrichingFactory", "eliteEnrichingFactory", "ultimateEnrichingFactory",
            "basicCrushingFactory", "advancedCrushingFactory", "eliteCrushingFactory", "ultimateCrushingFactory",
            "basicCombiningFactory", "advancedCombiningFactory", "eliteCombiningFactory", "ultimateCombiningFactory",
            "basicCompressingFactory", "advancedCompressingFactory", "eliteCompressingFactory", "ultimateCompressingFactory",
            "basicInfusingFactory", "advancedInfusingFactory", "eliteInfusingFactory", "ultimateInfusingFactory",
            "basicInjectingFactory", "advancedInjectingFactory", "eliteInjectingFactory", "ultimateInjectingFactory",
            "basicPurifyingFactory", "advancedPurifyingFactory", "elitePurifyingFactory", "ultimatePurifyingFactory",
            "basicSawingFactory", "advancedSawingFactory", "eliteSawingFactory", "ultimateSawingFactory",
            "basicSmeltingFactory", "advancedSmeltingFactory", "eliteSmeltingFactory", "ultimateSmeltingFactory"
        }
    },
    generators = {
        label = "Generators",
        color = colors.yellow,
        types = {
            "solarGenerator", "advancedSolarGenerator", "windGenerator",
            "heatGenerator", "bioGenerator", "gasBurningGenerator"
        }
    },
    multiblocks = {
        label = "Multiblocks",
        color = colors.purple,
        types = {
            "boilerValve", "turbineValve", "fissionReactorPort",
            "fusionReactorPort", "inductionPort", "spsPort",
            "thermalEvaporationController"
        }
    },
    logistics = {
        label = "Logistics",
        color = colors.orange,
        types = {
            "logisticalSorter", "digitalMiner", "qioExporter", "qioImporter"
        }
    }
}

-- Cache for peripheral type -> category mapping
local typeToCategory = nil

local function buildTypeCategoryMap()
    if typeToCategory then return typeToCategory end
    typeToCategory = {}

    for catName, catDef in pairs(MEKANISM_CATEGORIES) do
        for _, pType in ipairs(catDef.types) do
            typeToCategory[pType] = {
                category = catName,
                label = catDef.label,
                color = catDef.color,
                mod = "mekanism"
            }
        end
    end

    return typeToCategory
end

-- Detect if a peripheral supports activity monitoring
-- Returns: supported, strategyIndex
function MachineActivity.supportsActivity(p)
    if not p then return false, nil end

    for idx, strategy in ipairs(ACTIVITY_STRATEGIES) do
        if type(p[strategy.method]) == "function" then
            return true, idx
        end
    end

    return false, nil
end

-- Get activity state for a peripheral
-- Returns: isActive, activityData
function MachineActivity.getActivity(p)
    if not p then return false, {} end

    for _, strategy in ipairs(ACTIVITY_STRATEGIES) do
        if type(p[strategy.method]) == "function" then
            local ok, active, data = pcall(strategy.detect, p)
            if ok then
                return active, data or {}
            end
        end
    end

    return false, {}
end

-- Classify a peripheral type
-- Returns: { mod = "mekanism"|"mi"|"unknown", category = string, label = string, color = color }
function MachineActivity.classify(peripheralType)
    buildTypeCategoryMap()

    -- Check Mekanism
    if typeToCategory[peripheralType] then
        return typeToCategory[peripheralType]
    end

    -- Check for MI pattern (modern_industrialization:xxx)
    if peripheralType:match("^modern_industrialization:") then
        local shortName = peripheralType:match(":(.+)$") or peripheralType
        return {
            mod = "mi",
            category = "mi_machines",
            label = "MI: " .. shortName:gsub("_", " "),
            color = colors.blue
        }
    end

    -- Unknown mod
    return {
        mod = "unknown",
        category = "other",
        label = peripheralType,
        color = colors.lightGray
    }
end

-- Discover all machines with activity support
-- Returns: { [peripheralType] = { machines = {peripheral...}, classification = {...} } }
function MachineActivity.discoverAll()
    local result = {}
    local names = peripheral.getNames()

    for idx, name in ipairs(names) do
        local pType = peripheral.getType(name)
        if pType then
            local p = peripheral.wrap(name)
            local supported, _ = MachineActivity.supportsActivity(p)

            if supported then
                if not result[pType] then
                    result[pType] = {
                        machines = {},
                        classification = MachineActivity.classify(pType)
                    }
                end
                table.insert(result[pType].machines, {
                    peripheral = p,
                    name = name
                })
            end
        end
        Yield.check(idx, 10)
    end

    return result
end

-- Discover machines filtered by mod
-- modFilter: "all", "mekanism", "mi"
function MachineActivity.discover(modFilter)
    local all = MachineActivity.discoverAll()

    if modFilter == "all" then
        return all
    end

    local filtered = {}
    for pType, data in pairs(all) do
        if data.classification.mod == modFilter then
            filtered[pType] = data
        end
    end

    return filtered
end

-- Get available machine types as config options
-- modFilter: "all", "mekanism", "mi"
function MachineActivity.getMachineTypes(modFilter)
    local discovered = MachineActivity.discover(modFilter or "all")
    local types = {}

    for pType, data in pairs(discovered) do
        local label = data.classification.label
        local count = #data.machines
        table.insert(types, {
            value = pType,
            label = string.format("%s (%d)", label, count)
        })
    end

    -- Sort by label
    table.sort(types, function(a, b) return a.label < b.label end)

    return types
end

-- Get mod filter options
function MachineActivity.getModFilters()
    return {
        { value = "all", label = "All Mods" },
        { value = "mekanism", label = "Mekanism" },
        { value = "mi", label = "Modern Industrialization" }
    }
end

-- Group machines by category for dashboard display
-- Returns: { [category] = { label, color, types = { [pType] = {machines, active, total} } } }
function MachineActivity.groupByCategory(modFilter)
    local discovered = MachineActivity.discover(modFilter or "all")
    local groups = {}

    for pType, data in pairs(discovered) do
        local cat = data.classification.category

        if not groups[cat] then
            groups[cat] = {
                label = data.classification.label,
                color = data.classification.color,
                mod = data.classification.mod,
                types = {}
            }
        end

        -- Count active machines
        local activeCount = 0
        for _, machine in ipairs(data.machines) do
            local isActive, _ = MachineActivity.getActivity(machine.peripheral)
            if isActive then activeCount = activeCount + 1 end
        end

        groups[cat].types[pType] = {
            machines = data.machines,
            active = activeCount,
            total = #data.machines
        }
    end

    return groups
end

-- Get short display name for a peripheral type
function MachineActivity.getShortName(peripheralType)
    -- Remove mod prefix
    local name = peripheralType:match(":(.+)$") or peripheralType

    -- Shorten factory names
    name = name:gsub("^basic", "B.")
    name = name:gsub("^advanced", "A.")
    name = name:gsub("^elite", "E.")
    name = name:gsub("^ultimate", "U.")
    name = name:gsub("Factory$", "Fac")

    -- CamelCase to readable
    name = name:gsub("(%l)(%u)", "%1 %2")

    -- Truncate if too long
    if #name > 12 then
        name = name:sub(1, 11) .. "."
    end

    return name
end

return MachineActivity
