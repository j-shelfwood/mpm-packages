-- MekGeneratorStatus.lua
-- Mekanism generator status display with power output visualization

local BaseView = mpm('views/BaseView')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')
local MekSnapshotBus = mpm('peripherals/MekSnapshotBus')

-- Get available generators
local function getGeneratorOptions()
    return MekSnapshotBus.getGeneratorOptions()
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
    sleepTime = 1,

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
        return #MekSnapshotBus.getGeneratorOptions() > 0
    end,

    init = function(self, config)
        self.filterType = config.generator_type or "all"
    end,

    getData = function(self)
        local generators = MekSnapshotBus.getGenerators(self.filterType)
        local data = {
            generators = {},
            totalProduction = 0,
            maxProduction = 0
        }

        for idx, gen in ipairs(generators) do
            local shortName = gen.name:match("_(%d+)$") or tostring(idx)

            table.insert(data.generators, {
                name = shortName,
                type = gen.type,
                production = gen.production or 0,
                maxOutput = gen.maxOutput or 0,
                energyPct = gen.energyPct or 0,
                isActive = gen.isActive == true,
                extra = gen.extra or {}
            })

            data.totalProduction = data.totalProduction + (gen.production or 0)
            data.maxProduction = data.maxProduction + (gen.maxOutput or 0)

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

        -- Title with total production
        local title = "Generators: " .. formatRate(data.totalProduction)
        MonitorHelpers.writeCentered(self.monitor, 1, title, colors.yellow)

        -- Calculate layout
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

            -- Background based on activity
            local bgColor = gen.isActive and colors.green or colors.gray
            self.monitor.setBackgroundColor(bgColor)

            for i = 0, cellHeight - 1 do
                self.monitor.setCursorPos(x, y + i)
                self.monitor.write(string.rep(" ", cellWidth - 1))
            end

            -- Generator name
            self.monitor.setTextColor(colors.black)
            local typeShort = gen.type:gsub("Generator", ""):gsub("advanced", "Adv"):sub(1, cellWidth - 2)
            self.monitor.setCursorPos(x, y)
            self.monitor.write(typeShort)

            -- Production rate
            self.monitor.setCursorPos(x, y + 1)
            local rateStr = formatRate(gen.production):sub(1, cellWidth - 2)
            self.monitor.write(rateStr)

            -- Energy stored bar
            self.monitor.setCursorPos(x, y + 2)
            local barWidth = cellWidth - 2
            local filledWidth = math.floor(gen.energyPct * barWidth)
            self.monitor.setBackgroundColor(colors.red)
            self.monitor.write(string.rep(" ", barWidth))
            self.monitor.setCursorPos(x, y + 2)
            self.monitor.setBackgroundColor(colors.lime)
            self.monitor.write(string.rep(" ", filledWidth))

            -- Extra info line
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

        -- Status bar
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
