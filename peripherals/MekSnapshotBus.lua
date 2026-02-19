-- MekSnapshotBus.lua
-- Shared snapshot cache for Mekanism generator, multiblock, and single-machine views.

local Peripherals = mpm('utils/Peripherals')
local Activity = mpm('peripherals/MachineActivity')
local Text = mpm('utils/Text')

local MekSnapshotBus = {}

local DISCOVERY_REFRESH_MS = 5000
local SWEEP_INTERVAL_MS = 500
local FAST_POLL_MS = 1200
local MEDIUM_POLL_MS = 1800
local ERROR_POLL_MS = 3000

local GENERATOR_TYPES = {
    solarGenerator = true,
    advancedSolarGenerator = true,
    windGenerator = true,
    heatGenerator = true,
    bioGenerator = true,
    gasBurningGenerator = true
}

local MULTIBLOCK_TYPES = {
    boilerValve = {
        label = "Boiler",
        color = colors.orange,
        getStatus = function(p)
            local rate = p.getBoilRate and p.getBoilRate() or 0
            local capacity = p.getBoilCapacity and p.getBoilCapacity() or 1
            local temp = p.getTemperature and p.getTemperature() or 0
            local steamPct = p.getSteamFilledPercentage and p.getSteamFilledPercentage() or 0
            local waterPct = p.getWaterFilledPercentage and p.getWaterFilledPercentage() or 0
            return {
                active = rate > 0,
                primary = string.format("%.0f/%.0f mB/t", rate, capacity),
                secondary = string.format("%.0fK", temp),
                bars = {
                    { label = "Steam", pct = steamPct, color = colors.lightGray },
                    { label = "Water", pct = waterPct, color = colors.blue }
                }
            }
        end
    },
    turbineValve = {
        label = "Turbine",
        color = colors.cyan,
        getStatus = function(p)
            local production = p.getProductionRate and p.getProductionRate() or 0
            local flowRate = p.getFlowRate and p.getFlowRate() or 0
            local steamPct = p.getSteamFilledPercentage and p.getSteamFilledPercentage() or 0
            return {
                active = production > 0,
                primary = Text.formatEnergy(production, "J") .. "/t",
                secondary = string.format("Flow: %.0f mB/t", flowRate),
                bars = {
                    { label = "Steam", pct = steamPct, color = colors.lightGray }
                }
            }
        end
    },
    fissionReactorPort = {
        label = "Fission",
        color = colors.red,
        getStatus = function(p)
            local status = p.getStatus and p.getStatus() or false
            local damage = p.getDamagePercent and p.getDamagePercent() or 0
            local temp = p.getTemperature and p.getTemperature() or 0
            local fuelPct = p.getFuelFilledPercentage and p.getFuelFilledPercentage() or 0
            local wastePct = p.getWasteFilledPercentage and p.getWasteFilledPercentage() or 0
            local coolantPct = p.getCoolantFilledPercentage and p.getCoolantFilledPercentage() or 0
            return {
                active = status == true,
                primary = status and "ACTIVE" or "OFFLINE",
                secondary = string.format("%.0fK DMG:%.0f%%", temp, damage),
                bars = {
                    { label = "Fuel", pct = fuelPct, color = colors.yellow },
                    { label = "Waste", pct = wastePct, color = colors.brown },
                    { label = "Cool", pct = coolantPct, color = colors.lightBlue }
                },
                warning = damage > 0 or wastePct > 0.8
            }
        end
    },
    fusionReactorPort = {
        label = "Fusion",
        color = colors.magenta,
        getStatus = function(p)
            local ignited = p.isIgnited and p.isIgnited() or false
            local plasmaTemp = p.getPlasmaTemperature and p.getPlasmaTemperature() or 0
            local production = p.getProductionRate and p.getProductionRate() or 0
            local dtFuelPct = p.getDTFuelFilledPercentage and p.getDTFuelFilledPercentage() or 0
            local deutPct = p.getDeuteriumFilledPercentage and p.getDeuteriumFilledPercentage() or 0
            local tritPct = p.getTritiumFilledPercentage and p.getTritiumFilledPercentage() or 0
            return {
                active = ignited,
                primary = ignited and Text.formatEnergy(production, "J") .. "/t" or "COLD",
                secondary = string.format("Plasma: %.0fK", plasmaTemp),
                bars = {
                    { label = "D-T", pct = dtFuelPct, color = colors.purple },
                    { label = "D", pct = deutPct, color = colors.red },
                    { label = "T", pct = tritPct, color = colors.lime }
                }
            }
        end
    },
    inductionPort = {
        label = "Induction",
        color = colors.blue,
        getStatus = function(p)
            local energyPct = p.getEnergyFilledPercentage and p.getEnergyFilledPercentage() or 0
            local lastInput = p.getLastInput and p.getLastInput() or 0
            local lastOutput = p.getLastOutput and p.getLastOutput() or 0
            return {
                active = lastInput > 0 or lastOutput > 0,
                primary = string.format("%.1f%%", energyPct * 100),
                secondary = string.format("I:%s O:%s", Text.formatEnergy(lastInput, "J"), Text.formatEnergy(lastOutput, "J")),
                bars = {
                    { label = "Energy", pct = energyPct, color = colors.red }
                }
            }
        end
    },
    spsPort = {
        label = "SPS",
        color = colors.pink,
        getStatus = function(p)
            local processRate = p.getProcessRate and p.getProcessRate() or 0
            local inputPct = p.getInputFilledPercentage and p.getInputFilledPercentage() or 0
            local outputPct = p.getOutputFilledPercentage and p.getOutputFilledPercentage() or 0
            return {
                active = processRate > 0,
                primary = string.format("%.2f mB/t", processRate),
                secondary = "Antimatter",
                bars = {
                    { label = "Po", pct = inputPct, color = colors.lime },
                    { label = "AM", pct = outputPct, color = colors.pink }
                }
            }
        end
    },
    thermalEvaporationController = {
        label = "Evap",
        color = colors.yellow,
        getStatus = function(p)
            local production = p.getProductionAmount and p.getProductionAmount() or 0
            local temp = p.getTemperature and p.getTemperature() or 0
            local inputPct = p.getInputFilledPercentage and p.getInputFilledPercentage() or 0
            local outputPct = p.getOutputFilledPercentage and p.getOutputFilledPercentage() or 0
            return {
                active = production > 0,
                primary = string.format("%.1f mB/t", production),
                secondary = string.format("%.0fK", temp),
                bars = {
                    { label = "In", pct = inputPct, color = colors.blue },
                    { label = "Out", pct = outputPct, color = colors.white }
                }
            }
        end
    }
}

_G._shelfos_mekSnapshotBus = _G._shelfos_mekSnapshotBus or {
    running = false,
    refreshing = false,
    generators = {},
    generatorOrder = {},
    multiblocks = {},
    multiblockOrder = {},
    machines = {},
    machineOrder = {},
    pollCursorGen = 0,
    pollCursorMb = 0,
    pollCursorMachine = 0,
    lastDiscoveryAt = 0,
    lastSweepAt = 0
}

local function state()
    return _G._shelfos_mekSnapshotBus
end

local function nowMs()
    return os.epoch("utc")
end

local function pause(seconds)
    local timer = os.startTimer(seconds or 0)
    repeat
        local _, tid = os.pullEvent("timer")
    until tid == timer
end

local function safeCall(p, method)
    if not p or type(p[method]) ~= "function" then return nil end
    local ok, result = pcall(p[method])
    if ok then return result end
    return nil
end

local function tableCount(t)
    local n = 0
    for _ in pairs(t or {}) do
        n = n + 1
    end
    return n
end

local function pollGenerator(entry, now)
    local p = entry.peripheral
    if not p then
        entry.nextPollAt = now + ERROR_POLL_MS
        return false
    end

    local production = safeCall(p, "getProductionRate") or 0
    local maxOutput = safeCall(p, "getMaxOutput") or 0
    local energyPct = safeCall(p, "getEnergyFilledPercentage") or 0
    local extra = {}

    if entry.type == "solarGenerator" or entry.type == "advancedSolarGenerator" then
        extra.canSeeSun = safeCall(p, "canSeeSun") == true
    elseif entry.type == "heatGenerator" then
        extra.temperature = safeCall(p, "getTemperature") or 0
        extra.lavaPct = safeCall(p, "getLavaFilledPercentage") or 0
    elseif entry.type == "bioGenerator" then
        extra.fuelPct = safeCall(p, "getBioFuelFilledPercentage") or 0
    elseif entry.type == "gasBurningGenerator" then
        extra.fuelPct = safeCall(p, "getFuelFilledPercentage") or 0
        extra.burnRate = safeCall(p, "getBurnRate") or 0
    end

    entry.snapshot = {
        name = entry.name,
        type = entry.type,
        production = production,
        maxOutput = maxOutput,
        energyPct = energyPct,
        isActive = production > 0,
        extra = extra,
        updatedAt = now
    }
    entry.nextPollAt = now + FAST_POLL_MS
    return true
end

local function pollMultiblock(entry, now)
    local p = entry.peripheral
    local cfg = MULTIBLOCK_TYPES[entry.type]
    if not p or not cfg then
        entry.nextPollAt = now + ERROR_POLL_MS
        return false
    end

    local formed = safeCall(p, "isFormed")
    local status = { active = false, primary = "NOT FORMED", bars = {} }
    if formed then
        local ok, result = pcall(cfg.getStatus, p)
        if ok and type(result) == "table" then
            status = result
        end
    end

    entry.snapshot = {
        name = entry.name,
        type = entry.type,
        label = cfg.label,
        color = cfg.color,
        isFormed = formed == true,
        status = status,
        updatedAt = now
    }
    entry.nextPollAt = now + MEDIUM_POLL_MS
    return true
end

local function pollMachine(entry, now)
    local p = entry.peripheral
    if not p then
        entry.nextPollAt = now + ERROR_POLL_MS
        return false
    end

    local classification = entry.classification
    local data = {
        name = entry.name,
        type = entry.type,
        label = entry.shortName,
        category = classification and classification.category or "machine",
        color = classification and classification.color or colors.cyan
    }

    local isActive, activityData = Activity.getActivity(p)
    data.isActive = isActive
    data.activityData = activityData

    local energy = safeCall(p, "getEnergy")
    local maxEnergy = safeCall(p, "getMaxEnergy")
    local energyPct = safeCall(p, "getEnergyFilledPercentage")
    if type(energy) == "number" and type(maxEnergy) == "number" then
        data.energy = {
            current = energy,
            max = maxEnergy,
            pct = type(energyPct) == "number" and energyPct or (maxEnergy > 0 and (energy / maxEnergy) or 0)
        }
    end

    local progress = safeCall(p, "getRecipeProgress")
    local ticks = safeCall(p, "getTicksRequired")
    if type(progress) == "number" and type(ticks) == "number" and ticks > 0 then
        data.recipe = {
            progress = progress,
            total = ticks,
            pct = progress / ticks
        }
    end

    local production = safeCall(p, "getProductionRate")
    local maxOutput = safeCall(p, "getMaxOutput")
    if type(production) == "number" then
        data.production = {
            rate = production,
            max = type(maxOutput) == "number" and maxOutput or 0
        }
    end

    data.upgrades = safeCall(p, "getInstalledUpgrades")
    data.redstoneMode = safeCall(p, "getRedstoneMode")
    data.direction = safeCall(p, "getDirection")
    data.typeSpecific = {
        canSeeSun = safeCall(p, "canSeeSun"),
        temperature = safeCall(p, "getTemperature"),
        fluidPct = safeCall(p, "getFilledPercentage"),
        chemicalPct = safeCall(p, "getFilledPercentage")
    }

    entry.snapshot = data
    entry.updatedAt = now
    entry.nextPollAt = now + FAST_POLL_MS
    return true
end

local function refreshDiscovery()
    local st = state()
    if st.refreshing then
        return false
    end
    st.refreshing = true

    local ok, changed = pcall(function()
        local seenGen, seenMb, seenMachine = {}, {}, {}
        local names = Peripherals.getNames()
        local didChange = false

        for idx, name in ipairs(names) do
            local pType = Peripherals.getType(name)
            local p = Peripherals.wrap(name)

            if pType and GENERATOR_TYPES[pType] then
                seenGen[name] = true
                if not st.generators[name] then
                    st.generators[name] = { name = name, type = pType, peripheral = p, nextPollAt = 0, snapshot = nil }
                    didChange = true
                else
                    st.generators[name].type = pType
                    st.generators[name].peripheral = p
                end
            end

            if pType and MULTIBLOCK_TYPES[pType] then
                seenMb[name] = true
                if not st.multiblocks[name] then
                    st.multiblocks[name] = { name = name, type = pType, peripheral = p, nextPollAt = 0, snapshot = nil }
                    didChange = true
                else
                    st.multiblocks[name].type = pType
                    st.multiblocks[name].peripheral = p
                end
            end

            local supported = false
            if p then
                local okSupports = pcall(function()
                    supported = Activity.supportsActivity(p)
                end)
                if not okSupports then supported = false end
            end
            if supported and pType and Activity.classify(pType).mod == "mekanism" then
                seenMachine[name] = true
                if not st.machines[name] then
                    st.machines[name] = {
                        name = name,
                        type = pType,
                        peripheral = p,
                        classification = Activity.classify(pType),
                        shortName = Activity.getShortName(pType),
                        nextPollAt = 0,
                        snapshot = nil
                    }
                    didChange = true
                else
                    local entry = st.machines[name]
                    entry.type = pType
                    entry.peripheral = p
                    entry.classification = Activity.classify(pType)
                    entry.shortName = Activity.getShortName(pType)
                end
            end

            if idx % 20 == 0 then
                pause(0)
            end
        end

        for name in pairs(st.generators) do
            if not seenGen[name] then st.generators[name] = nil; didChange = true end
        end
        for name in pairs(st.multiblocks) do
            if not seenMb[name] then st.multiblocks[name] = nil; didChange = true end
        end
        for name in pairs(st.machines) do
            if not seenMachine[name] then st.machines[name] = nil; didChange = true end
        end

        if didChange then
            st.generatorOrder = {}
            for name in pairs(st.generators) do table.insert(st.generatorOrder, name) end
            table.sort(st.generatorOrder)

            st.multiblockOrder = {}
            for name in pairs(st.multiblocks) do table.insert(st.multiblockOrder, name) end
            table.sort(st.multiblockOrder)

            st.machineOrder = {}
            for name in pairs(st.machines) do table.insert(st.machineOrder, name) end
            table.sort(st.machineOrder)

            if st.pollCursorGen > #st.generatorOrder then st.pollCursorGen = 0 end
            if st.pollCursorMb > #st.multiblockOrder then st.pollCursorMb = 0 end
            if st.pollCursorMachine > #st.machineOrder then st.pollCursorMachine = 0 end
        end

        st.lastDiscoveryAt = nowMs()
        return didChange
    end)

    st.refreshing = false
    if not ok then return false end
    return changed
end

local function pollOrdered(entriesByName, ordered, cursorKey, budget, pollFn, now)
    local st = state()
    local total = #ordered
    if total == 0 then return false end

    local cursor = st[cursorKey] or 0
    local didWork = false
    local loops = math.min(total, budget)
    for i = 1, loops do
        cursor = (cursor % total) + 1
        local name = ordered[cursor]
        local entry = entriesByName[name]
        if entry and now >= (entry.nextPollAt or 0) then
            if pollFn(entry, now) then
                didWork = true
            end
        end
        if i % 6 == 0 then
            pause(0)
        end
    end
    st[cursorKey] = cursor
    return didWork
end

local function pollSweep()
    local st = state()
    local now = nowMs()
    local didWork = false

    if pollOrdered(st.generators, st.generatorOrder, "pollCursorGen", 20, pollGenerator, now) then
        didWork = true
    end
    if pollOrdered(st.multiblocks, st.multiblockOrder, "pollCursorMb", 16, pollMultiblock, now) then
        didWork = true
    end
    if pollOrdered(st.machines, st.machineOrder, "pollCursorMachine", 20, pollMachine, now) then
        didWork = true
    end

    st.lastSweepAt = now
    return didWork
end

function MekSnapshotBus.isRunning()
    return state().running == true
end

local function ensureFresh()
    local st = state()
    if MekSnapshotBus.isRunning() then
        return
    end
    if tableCount(st.generators) == 0 and tableCount(st.multiblocks) == 0 and tableCount(st.machines) == 0 then
        MekSnapshotBus.tick(true)
    end
end

function MekSnapshotBus.invalidate()
    local st = state()
    st.lastDiscoveryAt = 0
    st.lastSweepAt = 0
end

function MekSnapshotBus.tick(force)
    local st = state()
    local now = nowMs()
    local didWork = false

    if force or (now - (st.lastDiscoveryAt or 0)) >= DISCOVERY_REFRESH_MS then
        if refreshDiscovery() then
            didWork = true
        end
    end
    if force or (now - (st.lastSweepAt or 0)) >= SWEEP_INTERVAL_MS then
        if pollSweep() then
            didWork = true
        end
    end

    return didWork
end

function MekSnapshotBus.runLoop(runningRef)
    local st = state()
    st.running = true
    while runningRef.value do
        local didWork = MekSnapshotBus.tick(false)
        if not didWork then
            pause(0.1)
        end
    end
    st.running = false
end

function MekSnapshotBus.getGeneratorOptions()
    ensureFresh()
    local st = state()
    local counts = {}
    local total = 0
    for _, name in ipairs(st.generatorOrder) do
        local entry = st.generators[name]
        if entry then
            counts[entry.type] = (counts[entry.type] or 0) + 1
            total = total + 1
        end
    end

    local options = {}
    if total > 0 then
        table.insert(options, { value = "all", label = "All Generators (" .. total .. ")" })
    end
    for typeName, count in pairs(counts) do
        local label = typeName:gsub("(%l)(%u)", "%1 %2"):gsub("^%l", string.upper)
        table.insert(options, { value = typeName, label = label .. " (" .. count .. ")" })
    end
    table.sort(options, function(a, b) return a.label < b.label end)
    if #options > 0 and options[1].value ~= "all" then
        table.insert(options, 1, { value = "all", label = "All Generators (" .. total .. ")" })
    end
    return options
end

function MekSnapshotBus.getGenerators(filterType)
    ensureFresh()
    local st = state()
    local out = {}
    for _, name in ipairs(st.generatorOrder) do
        local entry = st.generators[name]
        if entry and entry.snapshot then
            if filterType == "all" or filterType == nil or entry.type == filterType then
                table.insert(out, entry.snapshot)
            end
        end
    end
    return out
end

function MekSnapshotBus.getMultiblockOptions()
    ensureFresh()
    local st = state()
    local counts = {}
    local total = 0
    for _, name in ipairs(st.multiblockOrder) do
        local entry = st.multiblocks[name]
        if entry then
            counts[entry.type] = (counts[entry.type] or 0) + 1
            total = total + 1
        end
    end

    local options = {}
    if total > 0 then
        table.insert(options, { value = "all", label = "All Multiblocks (" .. total .. ")" })
    end
    for typeName, cfg in pairs(MULTIBLOCK_TYPES) do
        local count = counts[typeName]
        if count and count > 0 then
            table.insert(options, { value = typeName, label = cfg.label .. " (" .. count .. ")" })
        end
    end
    return options
end

function MekSnapshotBus.getMultiblocks(filterType)
    ensureFresh()
    local st = state()
    local out = {}
    for _, name in ipairs(st.multiblockOrder) do
        local entry = st.multiblocks[name]
        if entry and entry.snapshot then
            if filterType == "all" or filterType == nil or entry.type == filterType then
                table.insert(out, entry.snapshot)
            end
        end
    end
    return out
end

function MekSnapshotBus.getMachineOptions()
    ensureFresh()
    local st = state()
    local options = {}
    for _, name in ipairs(st.machineOrder) do
        local entry = st.machines[name]
        if entry then
            local suffix = name:match("_(%d+)$") or "0"
            table.insert(options, {
                value = name,
                label = (entry.shortName or name) .. " (" .. suffix .. ")"
            })
        end
    end
    table.sort(options, function(a, b) return a.label < b.label end)
    return options
end

function MekSnapshotBus.getMachineDetail(name)
    ensureFresh()
    if not name then return nil end
    local entry = state().machines[name]
    if not entry then return nil end
    return entry.snapshot
end

function MekSnapshotBus.counts()
    local st = state()
    return {
        generators = #st.generatorOrder,
        multiblocks = #st.multiblockOrder,
        machines = #st.machineOrder
    }
end

return MekSnapshotBus
