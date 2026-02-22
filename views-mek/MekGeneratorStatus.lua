-- MekGeneratorStatus.lua
-- Mekanism generator status display with power output visualization

local BaseView = mpm('views/BaseView')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Peripherals = mpm('utils/Peripherals')
local Activity = mpm('peripherals/MachineActivity')
local Yield = mpm('utils/Yield')

local GENERATOR_TYPES = {
    solarGenerator = true,
    advancedSolarGenerator = true,
    windGenerator = true,
    heatGenerator = true,
    bioGenerator = true,
    gasBurningGenerator = true
}

local function safeCall(p, method, ...)
    if not p or type(p[method]) ~= "function" then return nil end
    local ok, result = pcall(p[method], ...)
    if ok then return result end
    return nil
end

local function discoverGenerators(filterType)
    local names = Peripherals.getNames()
    local found = {}
    for idx, name in ipairs(names) do
        local pType = Peripherals.getType(name)
        if pType and GENERATOR_TYPES[pType] then
            if filterType == "all" or filterType == nil or pType == filterType then
                local p = Peripherals.wrap(name)
                if p then
                    table.insert(found, { name = name, type = pType, peripheral = p })
                end
            end
        end
        Yield.check(idx, 20)
    end
    return found
end

local function getGeneratorOptions()
    local names = Peripherals.getNames()
    local counts = {}
    local total = 0
    for _, name in ipairs(names) do
        local pType = Peripherals.getType(name)
        if pType and GENERATOR_TYPES[pType] then
            counts[pType] = (counts[pType] or 0) + 1
            total = total + 1
        end
    end
    if total == 0 then return {} end
    local options = { { value = "all", label = "All Generators (" .. total .. ")" } }
    for typeName, count in pairs(counts) do
        local label = typeName:gsub("(%l)(%u)", "%1 %2"):gsub("^%l", string.upper)
        table.insert(options, { value = typeName, label = label .. " (" .. count .. ")" })
    end
    table.sort(options, function(a, b) return a.label < b.label end)
    return options
end

-- Format energy rate
local function formatRate(joules)
    if joules >= 1000000 then
        return string.format("%.1fMJ/t", joules / 1000000)
    elseif joules >= 1000 then
        return string.format("%.1fkJ/t", joules / 1000)
    else
        return string.format("%.0fJ/t", joules)
    end
end

return BaseView.custom({
    sleepTime = 2,
    listenEvents = {},

    configSchema = {
        {
            key = "generator_type",
            type = "select",
            label = "Generator Type",
            options = getGeneratorOptions,
            default = "all"
        }
    },

    mount = function()
        local names = Peripherals.getNames()
        for _, name in ipairs(names) do
            local pType = Peripherals.getType(name)
            if pType and GENERATOR_TYPES[pType] then return true end
        end
        return false
    end,

    init = function(self, config)
        self.filterType = config.generator_type or "all"
    end,

    getData = function(self)
        local generators = discoverGenerators(self.filterType)
        local data = { generators = {}, totalProduction = 0, maxProduction = 0 }

        for idx, gen in ipairs(generators) do
            local p = gen.peripheral
            local _, activity = Activity.getActivity(p)
            local production = (activity and activity.rate) or 0
            local maxOutput = safeCall(p, "getMaxOutput") or 0
            local energyPct = Activity.getEnergyPercent(p) or 0
            local extra = {}

            if gen.type == "solarGenerator" or gen.type == "advancedSolarGenerator" then
                extra.canSeeSun = safeCall(p, "canSeeSun") == true
            elseif gen.type == "heatGenerator" then
                extra.temperature = safeCall(p, "getTemperature") or 0
            elseif gen.type == "bioGenerator" then
                extra.fuelPct = safeCall(p, "getBioFuelFilledPercentage") or 0
            elseif gen.type == "gasBurningGenerator" then
                extra.fuelPct = safeCall(p, "getFuelFilledPercentage") or 0
            end

            local shortName = gen.name:match("_(%d+)$") or tostring(idx)
            table.insert(data.generators, {
                name = shortName,
                type = gen.type,
                production = production,
                maxOutput = maxOutput,
                energyPct = energyPct,
                isActive = production > 0,
                extra = extra
            })
            data.totalProduction = data.totalProduction + production
            data.maxProduction = data.maxProduction + maxOutput
            Yield.check(idx, 5)
        end

        return data
    end,

    render = function(self, data)
        local generators = data.generators

        if #generators == 0 then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No generators found", colors.orange)
            return
        end

        local title = "Generators: " .. formatRate(data.totalProduction)
        MonitorHelpers.writeCentered(self.monitor, 1, title, colors.yellow)

        local cellWidth = math.max(8, math.floor((self.width - 2) / math.min(#generators, 4)))
        local cellHeight = 4
        local cols = math.floor((self.width - 1) / cellWidth)
        if cols < 1 then cols = 1 end

        local startY = 3
        local activeCount = 0

        for idx, gen in ipairs(generators) do
            local col = (idx - 1) % cols
            local row = math.floor((idx - 1) / cols)
            local x = col * cellWidth + 1
            local y = startY + row * (cellHeight + 1)

            if y + cellHeight > self.height then break end

            local bgColor = gen.isActive and colors.green or colors.gray
            self.monitor.setBackgroundColor(bgColor)
            for i = 0, cellHeight - 1 do
                self.monitor.setCursorPos(x, y + i)
                self.monitor.write(string.rep(" ", cellWidth - 1))
            end

            self.monitor.setTextColor(colors.black)
            local typeShort = gen.type:gsub("Generator", ""):gsub("advanced", "Adv"):sub(1, cellWidth - 2)
            self.monitor.setCursorPos(x, y)
            self.monitor.write(typeShort)

            self.monitor.setCursorPos(x, y + 1)
            local rateStr = formatRate(gen.production):sub(1, cellWidth - 2)
            self.monitor.write(rateStr)

            self.monitor.setCursorPos(x, y + 2)
            local barWidth = cellWidth - 2
            local filledWidth = math.floor(gen.energyPct * barWidth)
            self.monitor.setBackgroundColor(colors.red)
            self.monitor.write(string.rep(" ", barWidth))
            self.monitor.setCursorPos(x, y + 2)
            self.monitor.setBackgroundColor(colors.lime)
            self.monitor.write(string.rep(" ", filledWidth))

            self.monitor.setBackgroundColor(bgColor)
            self.monitor.setTextColor(colors.black)
            self.monitor.setCursorPos(x, y + 3)
            local extraStr = ""
            if gen.extra.canSeeSun ~= nil then
                extraStr = gen.extra.canSeeSun and "Sun" or "Dark"
            elseif gen.extra.temperature then
                extraStr = string.format("%.0fK", gen.extra.temperature)
            elseif gen.extra.fuelPct then
                extraStr = string.format("F:%.0f%%", gen.extra.fuelPct * 100)
            end
            self.monitor.write(extraStr:sub(1, cellWidth - 2))

            if gen.isActive then activeCount = activeCount + 1 end
        end

        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(1, self.height)
        self.monitor.write(string.format("%d/%d producing", activeCount, #generators))
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Generator Status", colors.yellow)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "No Mekanism generators found", colors.gray)
    end
})
