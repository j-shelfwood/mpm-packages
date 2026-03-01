-- MachineActivity.lua
-- Unified machine activity detection across mods (MI, Mekanism, etc.)

local Yield = mpm('utils/Yield')
local Peripherals = mpm('utils/Peripherals')

local MachineActivity = {}
local discoveryCache = nil
local discoveryCacheAt = 0
local DISCOVERY_CACHE_TTL_MS = 5000
local WATCH_INTERVAL_MS = 1200
local MOD_MI = "modern_industrialization"

-- Common Modern Industrialization machine type names seen without mod prefixes.
-- These are treated as MI for dashboard grouping even when peripheral providers
-- omit `modern_industrialization:` in their type string.
local MI_TYPE_HINTS = {
    alloy_smelter = true,
    arc_furnace = true,
    electric_furnace = true,
    furnace = true,
    macerator = true,
    compressor = true,
    forge_hammer = true,
    wiremill = true,
    cutting_machine = true,
    cutter = true,
    bending_machine = true,
    mixer = true,
    canner = true,
    packer = true,
    unpacker = true,
    assembler = true,
    centrifuge = true,
    chemical_reactor = true,
    electrolyzer = true,
    distillery = true,
    blast_furnace = true,
    canning_machine = true,
    fluid_extractor = true,
    fluid_solidifier = true,
    laser_engraver = true,
    polarizer = true,
    plate_bender = true,
    recycler = true,
    scanner = true,
    replicator = true,
    thermal_centrifuge = true,
    ore_washer = true,
    vacuum_freezer = true,
    implosion_compressor = true,
    heat_exchanger = true,
    steam_blast_furnace = true,
    electric_quarry = true,
    steam_quarry = true,
    distillation_tower = true,
    oil_drilling_rig = true,
    fusion_reactor = true,
    industrial_electrolyzer = true,
    industrial_macerator = true,
    industrial_centrifuge = true,
    industrial_furnace = true,
    bronze_boiler = true,
    steel_boiler = true,
    diesel_generator = true,
    steam_turbine = true,
    large_boiler = true,
    electric_water_pump = true,
    lv_diesel_generator = true,
    mv_diesel_generator = true,
    hv_diesel_generator = true,
    lv_transformer = true,
    mv_transformer = true,
    hv_transformer = true,
    ev_transformer = true,
    iv_transformer = true
}

local function readValue(p, methodName, args)
    if not p or type(p[methodName]) ~= "function" then
        return nil
    end

    if p._isRemote and type(p.getCached) == "function" then
        if type(p.ensureSubscription) == "function" then
            p.ensureSubscription(methodName, args or {})
        end
        local cached = p.getCached(methodName, args or {})
        if type(cached) == "table" then
            return cached[1]
        end
        -- Fallback for remote methods without active subscriptions (for example
        -- MI activity methods like isBusy/getCraftingInformation). This keeps
        -- activity detection correct even when no cached snapshot exists yet.
        local okDirect, direct = pcall(p[methodName], table.unpack(args or {}))
        if okDirect then
            return direct
        end
        return nil
    end

    local ok, result = pcall(p[methodName], table.unpack(args or {}))
    if ok then
        return result
    end
    return nil
end

local function normalizeMiToken(value)
    if type(value) ~= "string" then
        return nil
    end
    local token = value:lower():gsub("[^%w_]", "")
    token = token:gsub("^(bronze_|steel_|primitive_)", "")
    token = token:gsub("^(ulv_|lv_|mv_|hv_|ev_|iv_|luv_|zpm_|uv_)", "")
    token = token:gsub("^electric_", "")
    return token
end

-- Activity detection strategies by method availability
local ACTIVITY_STRATEGIES = {
    -- Modern Industrialization integrations often expose this richer structure.
    { method = "getCraftingInformation", detect = function(p)
        local info = readValue(p, "getCraftingInformation")
        if type(info) ~= "table" then
            return nil, {}
        end
        -- UPW MI plugin returns an empty map when idle and a non-empty map only
        -- while an active recipe exists. Use this as a primary activity signal.
        local hasInfo = next(info) ~= nil
        if type(info.isActive) == "boolean" then
            return info.isActive, {}
        end
        local progress = info.progress
        if type(progress) ~= "number" then
            progress = info.recipeProgress
        end
        if type(progress) ~= "number" then
            progress = info.craftingProgress
        end
        local usage = info.currentRecipeCost
        if type(usage) ~= "number" then
            usage = info.baseRecipeCost
        end

        if type(progress) ~= "number" then
            -- If we got any crafting payload at all, mark as active (MI behavior).
            if hasInfo then
                local data = {}
                if type(usage) == "number" then
                    data.usage = usage
                end
                return true, data
            end
            -- Unknown shape; allow fallback to isBusy/isActive strategies.
            return nil, {}
        end
        local total = info.maxProgress
        if type(total) ~= "number" then
            total = info.progressMax
        end
        if type(total) ~= "number" or total <= 0 then
            total = 1
        end
        local active = hasInfo or (progress > 0 and progress < total)
        local data = {
            progress = progress,
            total = total,
            percent = total > 0 and (progress / total * 100) or 0
        }
        if type(usage) == "number" then
            data.usage = usage
        end
        return active, data
    end },

    -- Modern Industrialization / Generic
    { method = "isBusy", detect = function(p)
        local busy = readValue(p, "isBusy")
        if type(busy) == "boolean" then
            return busy, {}
        end
        return nil, {}
    end },

    -- Generic machine activity flags (some MI integrations expose these)
    { method = "isActive", detect = function(p)
        local active = readValue(p, "isActive")
        if type(active) == "boolean" then
            return active, {}
        end
        return nil, {}
    end },
    { method = "isRunning", detect = function(p)
        local active = readValue(p, "isRunning")
        if type(active) == "boolean" then
            return active, {}
        end
        return nil, {}
    end },

    -- Mekanism Processing (recipe progress)
    {
        method = "getRecipeProgress",
        detect = function(p)
            local progress = readValue(p, "getRecipeProgress", {0})
            if type(progress) ~= "number" then
                progress = readValue(p, "getRecipeProgress")
            end
            if type(progress) ~= "number" then
                return nil, {}
            end
            local total = 0
            if type(p.getTicksRequired) == "function" then
                local totalVal = readValue(p, "getTicksRequired")
                if type(totalVal) == "number" then total = totalVal end
            end
            local progressValue = progress or 0
            local active = progressValue > 0
            return active, {
                progress = progressValue,
                total = total,
                percent = total > 0 and (progressValue / total * 100) or 0
            }
        end
    },

    -- Generic progress-based activity (used by some non-Mekanism peripherals)
    {
        method = "getProgress",
        detect = function(p)
            local progress = readValue(p, "getProgress")
            if type(progress) ~= "number" then
                return nil, {}
            end
            local total = readValue(p, "getMaxProgress")
            if type(total) ~= "number" then
                total = readValue(p, "getProgressMax")
            end
            local progressValue = progress or 0
            local active = progressValue > 0
            return active, {
                progress = progressValue,
                total = type(total) == "number" and total or 0,
                percent = type(total) == "number" and total > 0 and (progressValue / total * 100) or 0
            }
        end
    },

    -- Mekanism Processing (energy usage)
    {
        method = "getEnergyUsage",
        detect = function(p)
            local usage = readValue(p, "getEnergyUsage")
            if type(usage) ~= "number" then return nil, {} end
            return (usage or 0) > 0, { usage = usage }
        end
    },

    -- Mekanism Generators (production rate)
    {
        method = "getProductionRate",
        detect = function(p)
            local rate = readValue(p, "getProductionRate")
            if type(rate) ~= "number" then return nil, {} end
            return (rate or 0) > 0, { rate = rate }
        end
    },

    -- Mekanism Multiblocks (formed + type-specific)
    {
        method = "isFormed",
        detect = function(p)
            local formedOk, formed = pcall(p.isFormed)
            if not formedOk then return nil, {} end
            if not formed then return false, { formed = false } end

            -- Check type-specific activity
            if p.getBoilRate then
                local rate = readValue(p, "getBoilRate")
                if type(rate) ~= "number" then return nil, { formed = true } end
                return (rate or 0) > 0, { formed = true, rate = rate }
            elseif p.getStatus then
                local status = readValue(p, "getStatus")
                if type(status) ~= "boolean" then return nil, { formed = true } end
                return status == true, { formed = true, status = status }
            elseif p.isIgnited then
                local ignited = readValue(p, "isIgnited")
                if type(ignited) ~= "boolean" then return nil, { formed = true } end
                return ignited and true or false, { formed = true, ignited = ignited }
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

    if p._isRemote and type(p.getActivitySnapshot) == "function" then
        local snapshot = p.getActivitySnapshot()
        if snapshot then
            -- Remote hosts can publish stale/older activity snapshots.
            -- Trust positive snapshots immediately, but allow local strategy
            -- evaluation to override a false idle snapshot.
            if snapshot.active then
                return true, snapshot.data or {}
            end
        end
    end

    for _, strategy in ipairs(ACTIVITY_STRATEGIES) do
        if type(p[strategy.method]) == "function" then
            local ok, active, data = pcall(strategy.detect, p)
            if ok and active ~= nil then
                return active, data or {}
            end
        end
    end

    return false, {}
end

function MachineActivity.getEnergyPercent(p)
    if not p then return nil end
    local pct = readValue(p, "getEnergyFilledPercentage")
    if type(pct) == "number" then
        return pct
    end
    local energy = readValue(p, "getEnergy")
    local maxEnergy = readValue(p, "getMaxEnergy")
    if type(energy) == "number" and type(maxEnergy) == "number" and maxEnergy > 0 then
        return energy / maxEnergy
    end
    return nil
end

function MachineActivity.getFormedState(p)
    if not p then return nil end
    local formed = readValue(p, "isFormed")
    if type(formed) == "boolean" then
        return formed
    end
    return nil
end

-- Classify a peripheral type
-- Returns: { mod = "mekanism"|MOD_MI|"unknown", category = string, label = string, color = color }
function MachineActivity.classify(peripheralType, peripheralName, peripheralObj)
    buildTypeCategoryMap()
    local normalizedType = (peripheralType or ""):lower()
    local shortName = tostring(peripheralType or ""):match(":(.+)$") or tostring(peripheralType or "")
    local displayName = tostring(peripheralName or shortName)
    local normalizedShort = normalizeMiToken(shortName) or ""
    local normalizedName = normalizeMiToken(peripheralName or "") or ""
    local hasMiCraftingInfo = peripheralObj and type(peripheralObj.getCraftingInformation) == "function"

    -- Check Mekanism
    local mekanismMatch = typeToCategory[peripheralType] or typeToCategory[shortName]
    if mekanismMatch then
        return mekanismMatch
    end

    -- Check for MI pattern (modern_industrialization:xxx and common variants)
    if normalizedType:match("^modern_industrialization:")
        or normalizedType:match("^modernindustrialization:")
        or normalizedType:find("modern_industrialization", 1, true)
        or normalizedType:find("modernindustrialization", 1, true)
        or normalizedType:match("^mi_")
        or normalizedType:match("mi_crafter")
        or normalizedType:match("_crafter$")
        or hasMiCraftingInfo then
        return {
            mod = MOD_MI,
            category = "mi_machines",
            label = "MI: " .. displayName:gsub("_", " "),
            color = colors.blue
        }
    end

    -- Fallback MI detection for providers that expose only short machine names.
    if MI_TYPE_HINTS[normalizedShort] or MI_TYPE_HINTS[normalizedName] then
        return {
            mod = MOD_MI,
            category = "mi_machines",
            label = "MI: " .. displayName:gsub("_", " "),
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
function MachineActivity.discoverAll(forceRefresh)
    local now = os.epoch("utc")
    if not forceRefresh and discoveryCache and (now - discoveryCacheAt) < DISCOVERY_CACHE_TTL_MS then
        return discoveryCache
    end

    local result = {}
    local names = {}
    local ok, fetched = pcall(Peripherals.getNames)
    if ok and type(fetched) == "table" then
        names = fetched
    end

    for idx, name in ipairs(names) do
        local pTypeOk, pType = pcall(Peripherals.getType, name)
        if pTypeOk and pType then
            local pOk, p = pcall(Peripherals.wrap, name)
            if not pOk then p = nil end
            local classification = MachineActivity.classify(pType, name, p)
            local supported, _ = MachineActivity.supportsActivity(p)
            local excluded = (pType == "me_bridge" or pType == "meBridge" or pType == "rs_bridge" or pType == "rsBridge")
            -- MI peripherals are included even if activity method detection is incomplete.
            -- This guarantees baseline telemetry (active=0 + optional energy/formed fields)
            -- instead of silently dropping all MI machines.
            local include = (supported or classification.mod == MOD_MI) and not excluded

            if include then
                if not result[pType] then
                    result[pType] = {
                        machines = {},
                        classification = classification
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

    discoveryCache = result
    discoveryCacheAt = now
    return result
end

-- Discover machines filtered by mod
-- modFilter: "all", "mekanism", "modern_industrialization" (legacy alias: "mi")
function MachineActivity.discover(modFilter, forceRefresh)
    local all = MachineActivity.discoverAll(forceRefresh)
    if modFilter == "mi" then
        modFilter = MOD_MI
    end

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

function MachineActivity.invalidateCache()
    discoveryCache = nil
    discoveryCacheAt = 0
end

-- Get available machine types as config options
-- modFilter: "all", "mekanism", "modern_industrialization" (legacy alias: "mi")
function MachineActivity.getMachineTypes(modFilter)
    local discovered = MachineActivity.discover(modFilter or "all")
    local types = {}

    for pType, data in pairs(discovered) do
        local shortName = MachineActivity.getShortName(pType)
        local label = shortName
        if data.classification.mod == MOD_MI then
            label = "MI: " .. shortName
        end
        local count = #data.machines
        table.insert(types, {
            value = pType,
            label = string.format("%s (%d)", label, count)
        })
    end

    -- Sort by label
    table.sort(types, function(a, b) return a.label < b.label end)

    table.insert(types, 1, { value = "all", label = "(All types)" })

    return types
end

function MachineActivity.getMachineTypeOptions(modFilter)
    return MachineActivity.getMachineTypes(modFilter)
end

function MachineActivity.normalizeMachineType(value)
    if value == "all" or value == nil then return nil end
    if type(value) == "table" then
        value = value.value
        if value == "all" or value == nil then return nil end
    end
    return value
end

function MachineActivity.buildTypeList(modFilter)
    local discovered = MachineActivity.discover(modFilter or "all")
    local types = {}

    for pType, data in pairs(discovered) do
        local shortName = MachineActivity.getShortName(pType)
        local label = data.classification.mod == MOD_MI and ("MI: " .. shortName) or shortName
        table.insert(types, {
            type = pType,
            label = label,
            shortName = shortName,
            classification = data.classification,
            machines = data.machines
        })
    end

    table.sort(types, function(a, b) return a.label < b.label end)
    return types
end

-- Build a machine entry with activity data and labels
-- @param machine {peripheral, name} from discover result
-- @param idx Numeric index fallback
-- @param pType Optional peripheral type string (e.g. "mekanism:enrichmentChamber")
function MachineActivity.buildMachineEntry(machine, idx, pType)
    local isActive, activityData = MachineActivity.getActivity(machine.peripheral)

    -- Short label for grid views (just ID number)
    local shortLabel = machine.name:match("_(%d+)$") or (idx and tostring(idx)) or machine.name

    -- Descriptive label for list views: "Enrich Chamber #3" style
    local typeStr = pType or machine.name:match("^(.-)_%d+$") or machine.name
    local shortName = MachineActivity.getShortName(typeStr)
    local idSuffix = machine.name:match("_(%d+)$")
    local fullLabel = shortName
    if idSuffix then
        fullLabel = shortName .. " #" .. idSuffix
    end

    return {
        label = shortLabel,
        fullLabel = fullLabel,
        shortName = shortName,
        name = machine.name,
        type = typeStr,
        peripheral = machine.peripheral,
        isActive = isActive,
        activity = activityData
    }
end

-- Get mod filter options
function MachineActivity.getModFilters()
    return {
        { value = "all", label = "All Mods" },
        { value = "mekanism", label = "Mekanism" },
        { value = MOD_MI, label = "Modern Industrialization" }
    }
end

-- Group machines by category (structure only, no activity polling)
-- Returns: { [category] = { label, color, types = { [pType] = {shortName, machines} } } }
-- Use this when the caller will poll activity itself to avoid double polling.
function MachineActivity.groupByCategoryRaw(modFilter)
    local discovered = MachineActivity.discover(modFilter or "all")
    local groups = {}

    for pType, data in pairs(discovered) do
        local cls = data.classification
        local cat = cls.category

        if not groups[cat] then
            -- Use Mekanism category label if available, otherwise classification label
            local catLabel = cls.label
            local catColor = cls.color
            if cls.mod == "mekanism" and MEKANISM_CATEGORIES[cat] then
                catLabel = MEKANISM_CATEGORIES[cat].label
                catColor = MEKANISM_CATEGORIES[cat].color
            end

            groups[cat] = {
                label = catLabel,
                color = catColor,
                mod = cls.mod,
                types = {}
            }
        end

        groups[cat].types[pType] = {
            shortName = MachineActivity.getShortName(pType),
            machines = data.machines
        }
    end

    return groups
end

-- Group machines by category for dashboard display (with activity polling)
-- Returns: { [category] = { label, color, types = { [pType] = {machines, active, total} } } }
-- NOTE: This polls activity for every machine. For views that render activity themselves,
-- prefer groupByCategoryRaw() to avoid double polling.
function MachineActivity.groupByCategory(modFilter)
    local groups = MachineActivity.groupByCategoryRaw(modFilter)

    for _, catData in pairs(groups) do
        for pType, typeInfo in pairs(catData.types) do
            local activeCount = 0
            for _, machine in ipairs(typeInfo.machines) do
                local isActive, _ = MachineActivity.getActivity(machine.peripheral)
                if isActive then activeCount = activeCount + 1 end
            end
            typeInfo.active = activeCount
            typeInfo.total = #typeInfo.machines
        end
    end

    return groups
end

-- Get human-readable display name for a peripheral type
-- Does NOT truncate — views handle truncation based on available width
function MachineActivity.getShortName(peripheralType)
    -- Remove mod prefix
    local name = peripheralType:match(":(.+)$") or peripheralType

    -- Shorten factory tier prefixes
    name = name:gsub("^basic", "B.")
    name = name:gsub("^advanced", "A.")
    name = name:gsub("^elite", "E.")
    name = name:gsub("^ultimate", "U.")
    name = name:gsub("Factory$", "Fac")

    -- CamelCase to readable (e.g., "enrichmentChamber" -> "Enrichment Chamber")
    name = name:gsub("(%l)(%u)", "%1 %2")

    -- Capitalize first letter
    name = name:sub(1, 1):upper() .. name:sub(2)

    return name
end

-- runLoop removed: it polled all machines every 1.2s and fired machine_status_transition
-- events that had zero consumers. Views poll MachineActivity.discoverAll() / getActivity()
-- directly in getData() on their own sleepTime timer. The discovery cache (5s TTL) provides
-- adequate deduplication. invalidateCache() is still called by Kernel on peripheral attach/detach.

return MachineActivity
