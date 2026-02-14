-- MekMultiblockStatus.lua
-- Mekanism multiblock status display (Boiler, Turbine, Fission, Fusion, etc.)

local BaseView = mpm('views/BaseView')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')
local Peripherals = mpm('utils/Peripherals')

-- Multiblock peripheral types and their display config
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
            local maxProd = p.getMaxProduction and p.getMaxProduction() or 1
            local flowRate = p.getFlowRate and p.getFlowRate() or 0
            local steamPct = p.getSteamFilledPercentage and p.getSteamFilledPercentage() or 0
            return {
                active = production > 0,
                primary = formatEnergy(production) .. "/t",
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
            local burnRate = p.getActualBurnRate and p.getActualBurnRate() or 0
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
            local caseTemp = p.getCaseTemperature and p.getCaseTemperature() or 0
            local production = p.getProductionRate and p.getProductionRate() or 0
            local dtFuelPct = p.getDTFuelFilledPercentage and p.getDTFuelFilledPercentage() or 0
            local deutPct = p.getDeuteriumFilledPercentage and p.getDeuteriumFilledPercentage() or 0
            local tritPct = p.getTritiumFilledPercentage and p.getTritiumFilledPercentage() or 0
            return {
                active = ignited,
                primary = ignited and formatEnergy(production) .. "/t" or "COLD",
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
            local transferCap = p.getTransferCap and p.getTransferCap() or 1
            return {
                active = lastInput > 0 or lastOutput > 0,
                primary = string.format("%.1f%%", energyPct * 100),
                secondary = string.format("I:%s O:%s", formatEnergy(lastInput), formatEnergy(lastOutput)),
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

-- Format energy values
function formatEnergy(joules)
    if joules >= 1000000000 then
        return string.format("%.1fGJ", joules / 1000000000)
    elseif joules >= 1000000 then
        return string.format("%.1fMJ", joules / 1000000)
    elseif joules >= 1000 then
        return string.format("%.1fkJ", joules / 1000)
    else
        return string.format("%.0fJ", joules)
    end
end

-- Discover multiblocks
local function findMultiblocks()
    local multiblocks = {}
    local names = Peripherals.getNames()

    for _, name in ipairs(names) do
        local pType = Peripherals.getType(name)
        if pType and MULTIBLOCK_TYPES[pType] then
            local p = Peripherals.wrap(name)
            -- Check if formed
            local formedOk, isFormed = pcall(p.isFormed)
            if formedOk then
                table.insert(multiblocks, {
                    peripheral = p,
                    name = name,
                    type = pType,
                    config = MULTIBLOCK_TYPES[pType],
                    isFormed = isFormed
                })
            end
        end
    end

    return multiblocks
end

-- Get multiblock type options
local function getMultiblockOptions()
    local multiblocks = findMultiblocks()
    local typeCounts = {}

    for _, mb in ipairs(multiblocks) do
        typeCounts[mb.type] = (typeCounts[mb.type] or 0) + 1
    end

    local options = {}
    if #multiblocks > 0 then
        table.insert(options, { value = "all", label = "All Multiblocks (" .. #multiblocks .. ")" })
    end

    for pType, config in pairs(MULTIBLOCK_TYPES) do
        if typeCounts[pType] then
            table.insert(options, {
                value = pType,
                label = config.label .. " (" .. typeCounts[pType] .. ")"
            })
        end
    end

    return options
end

return BaseView.custom({
    sleepTime = 1,

    configSchema = {
        {
            key = "multiblock_type",
            type = "select",
            label = "Multiblock Type",
            options = getMultiblockOptions,
            default = "all"
        }
    },

    mount = function()
        local multiblocks = findMultiblocks()
        return #multiblocks > 0
    end,

    init = function(self, config)
        self.filterType = config.multiblock_type or "all"
    end,

    getData = function(self)
        local multiblocks = findMultiblocks()
        local data = { multiblocks = {} }

        for idx, mb in ipairs(multiblocks) do
            if self.filterType == "all" or mb.type == self.filterType then
                local status = { active = false, primary = "NOT FORMED", bars = {} }

                if mb.isFormed then
                    local ok, s = pcall(mb.config.getStatus, mb.peripheral)
                    if ok then status = s end
                end

                table.insert(data.multiblocks, {
                    name = mb.name:match("_(%d+)$") or tostring(idx),
                    type = mb.type,
                    label = mb.config.label,
                    color = mb.config.color,
                    isFormed = mb.isFormed,
                    status = status
                })
            end
            Yield.check(idx, 3)
        end

        return data
    end,

    render = function(self, data)
        local multiblocks = data.multiblocks

        if #multiblocks == 0 then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No multiblocks found", colors.orange)
            return
        end

        -- Title
        MonitorHelpers.writeCentered(self.monitor, 1, "Multiblock Status", colors.white)

        -- Calculate layout - each multiblock gets a card
        local cardWidth = math.max(12, math.floor((self.width - 1) / math.min(#multiblocks, 3)))
        local cardHeight = 6
        local cols = math.floor(self.width / cardWidth)
        if cols < 1 then cols = 1 end

        local startY = 3
        local activeCount = 0
        local formedCount = 0

        for idx, mb in ipairs(multiblocks) do
            local col = (idx - 1) % cols
            local row = math.floor((idx - 1) / cols)
            local x = col * cardWidth + 1
            local y = startY + row * (cardHeight + 1)

            if y + cardHeight > self.height then break end

            local status = mb.status

            -- Card background
            local bgColor = colors.black
            if not mb.isFormed then
                bgColor = colors.red
            elseif status.warning then
                bgColor = colors.orange
            elseif status.active then
                bgColor = colors.green
            else
                bgColor = colors.gray
            end

            -- Draw card border/header
            self.monitor.setBackgroundColor(mb.color)
            self.monitor.setCursorPos(x, y)
            self.monitor.write(string.rep(" ", cardWidth - 1))
            self.monitor.setTextColor(colors.black)
            local headerText = mb.label:sub(1, cardWidth - 3)
            self.monitor.setCursorPos(x + 1, y)
            self.monitor.write(headerText)

            -- Card body
            self.monitor.setBackgroundColor(bgColor)
            for i = 1, cardHeight - 1 do
                self.monitor.setCursorPos(x, y + i)
                self.monitor.write(string.rep(" ", cardWidth - 1))
            end

            -- Primary status
            self.monitor.setTextColor(colors.white)
            self.monitor.setCursorPos(x + 1, y + 1)
            self.monitor.write((status.primary or ""):sub(1, cardWidth - 3))

            -- Secondary status
            self.monitor.setTextColor(colors.lightGray)
            self.monitor.setCursorPos(x + 1, y + 2)
            self.monitor.write((status.secondary or ""):sub(1, cardWidth - 3))

            -- Progress bars
            if status.bars then
                for barIdx, bar in ipairs(status.bars) do
                    if barIdx > 2 then break end  -- Max 2 bars
                    local barY = y + 2 + barIdx
                    local barWidth = cardWidth - 4
                    local filledWidth = math.floor((bar.pct or 0) * barWidth)

                    self.monitor.setCursorPos(x + 1, barY)
                    self.monitor.setBackgroundColor(colors.gray)
                    self.monitor.write(string.rep(" ", barWidth))
                    self.monitor.setCursorPos(x + 1, barY)
                    self.monitor.setBackgroundColor(bar.color or colors.green)
                    self.monitor.write(string.rep(" ", filledWidth))

                    -- Bar label
                    self.monitor.setBackgroundColor(bgColor)
                    self.monitor.setTextColor(colors.lightGray)
                    self.monitor.setCursorPos(x + barWidth + 2, barY)
                    self.monitor.write(bar.label:sub(1, 2))
                end
            end

            if status.active then activeCount = activeCount + 1 end
            if mb.isFormed then formedCount = formedCount + 1 end
        end

        -- Status bar
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(1, self.height)
        self.monitor.write(string.format("%d/%d active | %d/%d formed",
            activeCount, #multiblocks, formedCount, #multiblocks))
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Multiblock Status", colors.purple)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "No multiblocks found", colors.gray)
    end
})
