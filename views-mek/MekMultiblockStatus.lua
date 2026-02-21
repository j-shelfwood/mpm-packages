-- MekMultiblockStatus.lua
-- Mekanism multiblock status display (Boiler, Turbine, Fission, Fusion, etc.)

local BaseView = mpm('views/BaseView')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Text = mpm('utils/Text')
local Peripherals = mpm('utils/Peripherals')
local Yield = mpm('utils/Yield')

local MULTIBLOCK_TYPES = {
    boilerValve = { label = "Boiler", color = colors.orange },
    turbineValve = { label = "Turbine", color = colors.cyan },
    fissionReactorPort = { label = "Fission", color = colors.red },
    fusionReactorPort = { label = "Fusion", color = colors.magenta },
    inductionPort = { label = "Induction", color = colors.blue },
    spsPort = { label = "SPS", color = colors.pink },
    thermalEvaporationController = { label = "Evap", color = colors.yellow }
}

local function safeCall(p, method)
    if not p or type(p[method]) ~= "function" then return nil end
    local ok, result = pcall(p[method])
    if ok then return result end
    return nil
end

local function getMultiblockStatus(p, pType)
    local formed = safeCall(p, "isFormed")
    if not formed then
        return { active = false, primary = "NOT FORMED", bars = {} }
    end

    if pType == "boilerValve" then
        local rate = safeCall(p, "getBoilRate") or 0
        local capacity = safeCall(p, "getBoilCapacity") or 1
        local temp = safeCall(p, "getTemperature") or 0
        local steamPct = safeCall(p, "getSteamFilledPercentage") or 0
        local waterPct = safeCall(p, "getWaterFilledPercentage") or 0
        return { active = rate > 0,
            primary = string.format("%.0f/%.0f mB/t", rate, capacity),
            secondary = string.format("%.0fK", temp),
            bars = {{ label = "Steam", pct = steamPct, color = colors.lightGray },
                    { label = "Water", pct = waterPct, color = colors.blue }} }
    elseif pType == "turbineValve" then
        local production = safeCall(p, "getProductionRate") or 0
        local flowRate = safeCall(p, "getFlowRate") or 0
        local steamPct = safeCall(p, "getSteamFilledPercentage") or 0
        return { active = production > 0,
            primary = string.format("%.0fJ/t", production),
            secondary = string.format("Flow: %.0f mB/t", flowRate),
            bars = {{ label = "Steam", pct = steamPct, color = colors.lightGray }} }
    elseif pType == "fissionReactorPort" then
        local status = safeCall(p, "getStatus") or false
        local damage = safeCall(p, "getDamagePercent") or 0
        local temp = safeCall(p, "getTemperature") or 0
        local fuelPct = safeCall(p, "getFuelFilledPercentage") or 0
        local wastePct = safeCall(p, "getWasteFilledPercentage") or 0
        local coolantPct = safeCall(p, "getCoolantFilledPercentage") or 0
        return { active = status == true,
            primary = status and "ACTIVE" or "OFFLINE",
            secondary = string.format("%.0fK DMG:%.0f%%", temp, damage),
            warning = damage > 0 or wastePct > 0.8,
            bars = {{ label = "Fuel", pct = fuelPct, color = colors.yellow },
                    { label = "Waste", pct = wastePct, color = colors.brown },
                    { label = "Cool", pct = coolantPct, color = colors.lightBlue }} }
    elseif pType == "fusionReactorPort" then
        local ignited = safeCall(p, "isIgnited") or false
        local plasmaTemp = safeCall(p, "getPlasmaTemperature") or 0
        local production = safeCall(p, "getProductionRate") or 0
        local dtFuelPct = safeCall(p, "getDTFuelFilledPercentage") or 0
        return { active = ignited,
            primary = ignited and string.format("%.0fJ/t", production) or "COLD",
            secondary = string.format("Plasma: %.0fK", plasmaTemp),
            bars = {{ label = "D-T", pct = dtFuelPct, color = colors.purple }} }
    elseif pType == "inductionPort" then
        local energyPct = safeCall(p, "getEnergyFilledPercentage") or 0
        local lastInput = safeCall(p, "getLastInput") or 0
        local lastOutput = safeCall(p, "getLastOutput") or 0
        return { active = lastInput > 0 or lastOutput > 0,
            primary = string.format("%.1f%%", energyPct * 100),
            secondary = string.format("I:%.0f O:%.0f", lastInput, lastOutput),
            bars = {{ label = "Energy", pct = energyPct, color = colors.red }} }
    elseif pType == "spsPort" then
        local processRate = safeCall(p, "getProcessRate") or 0
        local inputPct = safeCall(p, "getInputFilledPercentage") or 0
        local outputPct = safeCall(p, "getOutputFilledPercentage") or 0
        return { active = processRate > 0,
            primary = string.format("%.2f mB/t", processRate),
            secondary = "Antimatter",
            bars = {{ label = "Po", pct = inputPct, color = colors.lime },
                    { label = "AM", pct = outputPct, color = colors.pink }} }
    elseif pType == "thermalEvaporationController" then
        local production = safeCall(p, "getProductionAmount") or 0
        local temp = safeCall(p, "getTemperature") or 0
        local inputPct = safeCall(p, "getInputFilledPercentage") or 0
        local outputPct = safeCall(p, "getOutputFilledPercentage") or 0
        return { active = production > 0,
            primary = string.format("%.1f mB/t", production),
            secondary = string.format("%.0fK", temp),
            bars = {{ label = "In", pct = inputPct, color = colors.blue },
                    { label = "Out", pct = outputPct, color = colors.white }} }
    end

    return { active = true, primary = "Formed", bars = {} }
end

local function getMultiblockOptions()
    local names = Peripherals.getNames()
    local counts = {}
    local total = 0
    for _, name in ipairs(names) do
        local pType = Peripherals.getType(name)
        if pType and MULTIBLOCK_TYPES[pType] then
            counts[pType] = (counts[pType] or 0) + 1
            total = total + 1
        end
    end
    if total == 0 then return {} end
    local options = { { value = "all", label = "All Multiblocks (" .. total .. ")" } }
    for pType, cfg in pairs(MULTIBLOCK_TYPES) do
        local count = counts[pType]
        if count and count > 0 then
            table.insert(options, { value = pType, label = cfg.label .. " (" .. count .. ")" })
        end
    end
    return options
end

return BaseView.custom({
    sleepTime = 2,
    listenEvents = {},

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
        local names = Peripherals.getNames()
        for _, name in ipairs(names) do
            local pType = Peripherals.getType(name)
            if pType and MULTIBLOCK_TYPES[pType] then return true end
        end
        return false
    end,

    init = function(self, config)
        self.filterType = config.multiblock_type or "all"
    end,

    getData = function(self)
        local names = Peripherals.getNames()
        local data = { multiblocks = {} }

        for idx, name in ipairs(names) do
            local pType = Peripherals.getType(name)
            local cfg = pType and MULTIBLOCK_TYPES[pType]
            if cfg then
                if self.filterType == "all" or self.filterType == pType then
                    local p = Peripherals.wrap(name)
                    if p then
                        local status = getMultiblockStatus(p, pType)
                        local formed = safeCall(p, "isFormed") == true
                        table.insert(data.multiblocks, {
                            name = name:match("_(%d+)$") or tostring(idx),
                            type = pType,
                            label = cfg.label,
                            color = cfg.color,
                            isFormed = formed,
                            status = status
                        })
                    end
                end
            end
            Yield.check(idx, 10)
        end

        return data
    end,

    render = function(self, data)
        local multiblocks = data.multiblocks

        if #multiblocks == 0 then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No multiblocks found", colors.orange)
            return
        end

        MonitorHelpers.writeCentered(self.monitor, 1, "Multiblock Status", colors.white)

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

            self.monitor.setBackgroundColor(mb.color)
            self.monitor.setCursorPos(x, y)
            self.monitor.write(string.rep(" ", cardWidth - 1))
            self.monitor.setTextColor(colors.black)
            local headerText = mb.label:sub(1, cardWidth - 3)
            self.monitor.setCursorPos(x + 1, y)
            self.monitor.write(headerText)

            self.monitor.setBackgroundColor(bgColor)
            for i = 1, cardHeight - 1 do
                self.monitor.setCursorPos(x, y + i)
                self.monitor.write(string.rep(" ", cardWidth - 1))
            end

            self.monitor.setTextColor(colors.white)
            self.monitor.setCursorPos(x + 1, y + 1)
            self.monitor.write((status.primary or ""):sub(1, cardWidth - 3))

            self.monitor.setTextColor(colors.lightGray)
            self.monitor.setCursorPos(x + 1, y + 2)
            self.monitor.write((status.secondary or ""):sub(1, cardWidth - 3))

            if status.bars then
                for barIdx, bar in ipairs(status.bars) do
                    if barIdx > 2 then break end
                    local barY = y + 2 + barIdx
                    local barWidth = cardWidth - 4
                    local filledWidth = math.floor((bar.pct or 0) * barWidth)

                    self.monitor.setCursorPos(x + 1, barY)
                    self.monitor.setBackgroundColor(colors.gray)
                    self.monitor.write(string.rep(" ", barWidth))
                    self.monitor.setCursorPos(x + 1, barY)
                    self.monitor.setBackgroundColor(bar.color or colors.green)
                    self.monitor.write(string.rep(" ", filledWidth))

                    self.monitor.setBackgroundColor(bgColor)
                    self.monitor.setTextColor(colors.lightGray)
                    self.monitor.setCursorPos(x + barWidth + 2, barY)
                    self.monitor.write(bar.label:sub(1, 2))
                end
            end

            if status.active then activeCount = activeCount + 1 end
            if mb.isFormed then formedCount = formedCount + 1 end
        end

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
