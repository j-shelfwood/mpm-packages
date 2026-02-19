-- MekMachineGauge.lua
-- Single Mekanism machine detailed status display

local BaseView = mpm('views/BaseView')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Text = mpm('utils/Text')
local Yield = mpm('utils/Yield')
local Activity = mpm('peripherals/MachineActivity')
local MekSnapshotBus = mpm('peripherals/MekSnapshotBus')

-- Get all Mekanism machines as options
local function getMachineOptions()
    return MekSnapshotBus.getMachineOptions()
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
    sleepTime = 1,

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
        return MekSnapshotBus.getMachineDetail(self.machineName)
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
