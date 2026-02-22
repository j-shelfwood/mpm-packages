-- MekMachineGauge.lua
-- Single Mekanism machine detailed status display

local BaseView = mpm('views/BaseView')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Text = mpm('utils/Text')
local Peripherals = mpm('utils/Peripherals')
local Activity = mpm('peripherals/MachineActivity')

local listenEvents = {}

local function safeCall(p, method)
    if not p or type(p[method]) ~= "function" then return nil end
    local ok, result = pcall(p[method])
    if ok then return result end
    return nil
end

-- Get all Mekanism machines as options (direct peripheral scan)
local function getMachineOptions()
    local names = Peripherals.getNames()
    local options = {}
    for _, name in ipairs(names) do
        local pType = Peripherals.getType(name)
        if pType then
            local cls = Activity.classify(pType)
            if cls and cls.mod == "mekanism" then
                local p = Peripherals.wrap(name)
                if p and Activity.supportsActivity(p) then
                    local suffix = name:match("_(%d+)$") or "0"
                    local shortName = Activity.getShortName(pType)
                    table.insert(options, {
                        value = name,
                        label = shortName .. " (" .. suffix .. ")"
                    })
                end
            end
        end
    end
    table.sort(options, function(a, b) return a.label < b.label end)
    return options
end

-- Draw a progress bar
local function drawProgressBar(monitor, x, y, width, pct, fgColor, bgColor, label)
    MonitorHelpers.drawProgressBar(monitor, x, y, width, pct * 100, fgColor or colors.green, bgColor or colors.gray, false)
    local filledWidth = math.floor(pct * width)

    -- Label overlay
    if label then
        monitor.setCursorPos(x + 1, y)
        monitor.setTextColor(colors.white)
        monitor.setBackgroundColor(filledWidth > #label + 2 and fgColor or bgColor)
        monitor.write(label)
    end
end

return BaseView.custom({
    sleepTime = 2,
    listenEvents = listenEvents,

    configSchema = {
        {
            key = "machine_name",
            type = "select",
            label = "Machine",
            options = getMachineOptions,
            required = true
        }
    },

    mount = function()
        local options = getMachineOptions()
        return #options > 0
    end,

    init = function(self, config)
        self.machineName = config.machine_name
    end,

    getData = function(self)
        if not self.machineName then return nil end
        local p = Peripherals.wrap(self.machineName)
        if not p then return nil end
        local pType = Peripherals.getType(self.machineName)
        local cls = pType and Activity.classify(pType) or {}
        local isActive, activityData = Activity.getActivity(p)

        local data = {
            name = self.machineName,
            type = pType or self.machineName,
            label = pType and Activity.getShortName(pType) or self.machineName,
            category = cls.category or "machine",
            color = cls.color or colors.cyan,
            isActive = isActive,
            activityData = activityData,
            typeSpecific = {
                canSeeSun = safeCall(p, "canSeeSun"),
                temperature = safeCall(p, "getTemperature"),
            }
        }

        local energy = safeCall(p, "getEnergy")
        local maxEnergy = safeCall(p, "getMaxEnergy")
        local energyPct = Activity.getEnergyPercent(p)
        if type(energy) == "number" and type(maxEnergy) == "number" then
            data.energy = {
                current = energy,
                max = maxEnergy,
                pct = type(energyPct) == "number" and energyPct or (maxEnergy > 0 and (energy / maxEnergy) or 0)
            }
        end

        if type(activityData.progress) == "number"
            and type(activityData.total) == "number"
            and activityData.total > 0 then
            local pct = activityData.percent or (activityData.progress / activityData.total)
            data.recipe = { progress = activityData.progress, total = activityData.total, pct = pct }
        end

        if type(activityData.rate) == "number" then
            local maxOutput = safeCall(p, "getMaxOutput")
            data.production = { rate = activityData.rate, max = type(maxOutput) == "number" and maxOutput or 0 }
        end

        data.upgrades = safeCall(p, "getInstalledUpgrades")
        data.redstoneMode = safeCall(p, "getRedstoneMode")

        return data
    end,

    render = function(self, data)
        if not data then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "Machine not found", colors.red)
            return
        end

        -- Title bar with machine type
        self.monitor.setBackgroundColor(data.color or colors.cyan)
        self.monitor.setCursorPos(1, 1)
        self.monitor.write(string.rep(" ", self.width))
        self.monitor.setTextColor(colors.black)
        MonitorHelpers.writeCentered(self.monitor, 1, data.label, colors.black)

        -- Status indicator
        self.monitor.setBackgroundColor(colors.black)
        local statusColor = data.isActive and colors.green or colors.gray
        local statusText = data.isActive and "ACTIVE" or "IDLE"
        self.monitor.setCursorPos(self.width - #statusText, 1)
        self.monitor.setBackgroundColor(statusColor)
        self.monitor.setTextColor(colors.white)
        self.monitor.write(statusText)

        local y = 3
        self.monitor.setBackgroundColor(colors.black)

        -- Energy bar
        if data.energy then
            self.monitor.setTextColor(colors.yellow)
            self.monitor.setCursorPos(1, y)
            self.monitor.write("Energy:")
            y = y + 1

            drawProgressBar(self.monitor, 1, y, self.width - 1, data.energy.pct,
                colors.red, colors.gray,
                string.format("%.1f%%", data.energy.pct * 100))
            y = y + 1

            self.monitor.setTextColor(colors.lightGray)
            self.monitor.setCursorPos(1, y)
            self.monitor.write(Text.formatEnergy(data.energy.current, "J") .. " / " .. Text.formatEnergy(data.energy.max, "J"))
            y = y + 2
        end

        -- Recipe progress
        if data.recipe then
            self.monitor.setTextColor(colors.lime)
            self.monitor.setCursorPos(1, y)
            self.monitor.write("Progress:")
            y = y + 1

            drawProgressBar(self.monitor, 1, y, self.width - 1, data.recipe.pct,
                colors.green, colors.gray,
                string.format("%.0f%%", data.recipe.pct * 100))
            y = y + 1

            self.monitor.setTextColor(colors.lightGray)
            self.monitor.setCursorPos(1, y)
            self.monitor.write(string.format("%d / %d ticks", data.recipe.progress, data.recipe.total))
            y = y + 2
        end

        -- Production rate (generators)
        if data.production and data.production.rate > 0 then
            self.monitor.setTextColor(colors.yellow)
            self.monitor.setCursorPos(1, y)
            self.monitor.write("Output: " .. Text.formatEnergy(data.production.rate, "J") .. "/t")
            y = y + 1

            if data.production.max > 0 then
                local prodPct = data.production.rate / data.production.max
                drawProgressBar(self.monitor, 1, y, self.width - 1, prodPct,
                    colors.yellow, colors.gray, nil)
                y = y + 1
            end
            y = y + 1
        end

        -- Type-specific info
        if data.typeSpecific.canSeeSun ~= nil then
            self.monitor.setTextColor(data.typeSpecific.canSeeSun and colors.yellow or colors.gray)
            self.monitor.setCursorPos(1, y)
            self.monitor.write(data.typeSpecific.canSeeSun and "Sunlight: YES" or "Sunlight: NO")
            y = y + 1
        end

        if data.typeSpecific.temperature then
            self.monitor.setTextColor(colors.orange)
            self.monitor.setCursorPos(1, y)
            self.monitor.write(string.format("Temp: %.0fK", data.typeSpecific.temperature))
            y = y + 1
        end

        -- Upgrades
        if data.upgrades and next(data.upgrades) then
            self.monitor.setTextColor(colors.purple)
            self.monitor.setCursorPos(1, y)
            self.monitor.write("Upgrades:")
            y = y + 1

            self.monitor.setTextColor(colors.lightGray)
            local upgradeStr = ""
            for upgrade, count in pairs(data.upgrades) do
                local short = upgrade:sub(1, 3):upper()
                upgradeStr = upgradeStr .. short .. ":" .. count .. " "
            end
            self.monitor.setCursorPos(1, y)
            self.monitor.write(upgradeStr:sub(1, self.width - 1))
            y = y + 1
        end

        -- Redstone mode
        if data.redstoneMode then
            self.monitor.setTextColor(colors.red)
            self.monitor.setCursorPos(1, self.height - 1)
            self.monitor.write("RS: " .. data.redstoneMode)
        end

        -- Machine ID at bottom
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(1, self.height)
        self.monitor.write(data.name:sub(1, self.width - 1))
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Machine Gauge", colors.cyan)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Select a machine to monitor", colors.gray)
    end
})
