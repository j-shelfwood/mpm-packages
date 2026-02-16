-- MachineList.lua
-- Browseable list of machines with detail overlay

local BaseView = mpm('views/BaseView')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Text = mpm('utils/Text')
local Core = mpm('ui/Core')
local Overlay = mpm('ui/Overlay')
local Yield = mpm('utils/Yield')
local Activity = mpm('peripherals/MachineActivity')

local function safeCall(p, method, ...)
    if not p or type(p[method]) ~= "function" then return nil end
    local ok, result = pcall(p[method], ...)
    if ok then return result end
    return nil
end

local function formatPercent(value)
    if value == nil then return nil end
    return string.format("%.0f%%", value * 100)
end

local function buildDetailLines(machine)
    local lines = {}

    local function addLine(label, value, color)
        if value == nil or value == "" then return end
        table.insert(lines, { text = label .. ": " .. tostring(value), color = color or colors.white })
    end

    addLine("Name", machine.name, colors.white)
    addLine("Type", machine.type, colors.lightGray)
    addLine("Active", machine.isActive and "YES" or "NO", machine.isActive and colors.lime or colors.gray)

    local activity = machine.activity or {}
    if activity.progress then
        local pct = activity.total and activity.total > 0 and (activity.progress / activity.total) or 0
        addLine("Progress", string.format("%d/%d (%s)", activity.progress, activity.total or 0, formatPercent(pct) or "0%"), colors.yellow)
    end
    if activity.usage then addLine("Energy Use", Text.formatEnergy(activity.usage, "J"), colors.orange) end
    if activity.rate then addLine("Rate", Text.formatEnergy(activity.rate, "J") .. "/t", colors.yellow) end
    if activity.formed ~= nil then addLine("Formed", activity.formed and "YES" or "NO", colors.lightGray) end
    if activity.status ~= nil then addLine("Status", tostring(activity.status), colors.lightGray) end
    if activity.ignited ~= nil then addLine("Ignited", activity.ignited and "YES" or "NO", colors.red) end

    local p = machine.peripheral
    local energy = safeCall(p, "getEnergy")
    local maxEnergy = safeCall(p, "getMaxEnergy")
    local energyPct = safeCall(p, "getEnergyFilledPercentage")
    if energy and maxEnergy then
        local pct = energyPct or (maxEnergy > 0 and (energy / maxEnergy) or 0)
        addLine("Energy", Text.formatEnergy(energy, "J") .. " / " .. Text.formatEnergy(maxEnergy, "J"), colors.yellow)
        addLine("Energy %", formatPercent(pct), colors.yellow)
    end

    local progress = safeCall(p, "getRecipeProgress")
    local ticks = safeCall(p, "getTicksRequired")
    if progress and ticks and ticks > 0 then
        addLine("Recipe", string.format("%d/%d (%s)", progress, ticks, formatPercent(progress / ticks)), colors.lime)
    end

    local rate = safeCall(p, "getProductionRate")
    local maxRate = safeCall(p, "getMaxOutput")
    if rate then
        if maxRate and maxRate > 0 then
            addLine("Output", Text.formatEnergy(rate, "J") .. "/t (" .. formatPercent(rate / maxRate) .. ")", colors.orange)
        else
            addLine("Output", Text.formatEnergy(rate, "J") .. "/t", colors.orange)
        end
    end

    local upgrades = safeCall(p, "getInstalledUpgrades")
    if upgrades and next(upgrades) then
        local parts = {}
        for upgrade, count in pairs(upgrades) do
            table.insert(parts, upgrade:sub(1, 3):upper() .. ":" .. count)
        end
        table.sort(parts)
        addLine("Upgrades", table.concat(parts, " "), colors.purple)
    end

    local redstone = safeCall(p, "getRedstoneMode")
    if redstone then addLine("Redstone", redstone, colors.red) end

    local direction = safeCall(p, "getDirection")
    if direction then addLine("Direction", direction, colors.lightGray) end

    local temp = safeCall(p, "getTemperature")
    if temp then addLine("Temp", string.format("%.0fK", temp), colors.orange) end

    local canSeeSun = safeCall(p, "canSeeSun")
    if canSeeSun ~= nil then addLine("Sunlight", canSeeSun and "YES" or "NO", colors.yellow) end

    local filledPct = safeCall(p, "getFilledPercentage")
    if filledPct then addLine("Filled", formatPercent(filledPct), colors.cyan) end

    return lines
end

local function showDetailOverlay(self, machine)
    local monitor = self.monitor
    local overlay = Overlay.new(monitor, { footerHeight = 1 })
    local title = Activity.getShortName(machine.type) or "Machine"
    local lines = buildDetailLines(machine)
    local maxLines = math.max(4, math.min(#lines, self.height - 6))

    if #lines > maxLines then
        local remaining = #lines - maxLines
        lines = { table.unpack(lines, 1, maxLines) }
        table.insert(lines, { text = "+" .. remaining .. " more...", color = colors.gray })
    end

    overlay:show(title, lines)

    local x1, y1, x2, y2 = overlay:getBounds()
    local fx1, fy1 = overlay:getFooterBounds()

    monitor.setBackgroundColor(colors.gray)
    monitor.setTextColor(colors.red)
    monitor.setCursorPos(fx1, fy1)
    monitor.write("[Close]")
    Core.resetColors(monitor)

    local monitorName = self.peripheralName
    while true do
        local event, side, x, y = os.pullEvent("monitor_touch")
        if side == monitorName then
            if (y == fy1 and x >= fx1 and x <= fx1 + 6) or
               x < x1 or x > x2 or y < y1 or y > y2 then
                overlay:hide()
                return
            end
        end
    end
end

return BaseView.interactive({
    sleepTime = 1,

    configSchema = {
        {
            key = "mod_filter",
            type = "select",
            label = "Mod Filter",
            options = Activity.getModFilters,
            default = "all"
        },
        {
            key = "machine_type",
            type = "select",
            label = "Machine Type",
            options = function(config)
                return Activity.getMachineTypeOptions((config and config.mod_filter) or "all")
            end
        }
    },

    mount = function()
        local discovered = Activity.discoverAll()
        return next(discovered) ~= nil
    end,

    init = function(self, config)
        self.modFilter = config.mod_filter or "all"
        self.machineType = Activity.normalizeMachineType(config.machine_type)
        self.typeIndex = 1
    end,

    getData = function(self)
        local types = Activity.buildTypeList(self.modFilter)
        self._types = types

        if self.machineType then
            for idx, info in ipairs(types) do
                if info.type == self.machineType then
                    self.typeIndex = idx
                    break
                end
            end
        else
            self.typeIndex = math.max(1, math.min(self.typeIndex or 1, #types))
        end

        local current = types[self.typeIndex]
        if not current then return {} end

        local items = {}
        local activeCount = 0
        local totalMachines = #current.machines

        if not self.machineType and #types > 1 then
            table.insert(items, { kind = "nav", dir = "prev", label = "<< Prev type" })
        end

        for idx, machine in ipairs(current.machines) do
            local entry = Activity.buildMachineEntry(machine, idx)
            if entry.isActive then activeCount = activeCount + 1 end
            entry.kind = "machine"
            entry.type = current.type
            table.insert(items, entry)
            Yield.check(idx, 10)
        end

        if not self.machineType and #types > 1 then
            table.insert(items, { kind = "nav", dir = "next", label = "Next type >>" })
        end

        self._currentHeader = {
            label = current.label,
            active = activeCount,
            total = totalMachines
        }

        return items
    end,

    header = function(self)
        if not self._currentHeader then return "Machines" end
        return {
            text = self._currentHeader.label,
            secondary = string.format(" %d/%d", self._currentHeader.active, self._currentHeader.total)
        }
    end,

    formatItem = function(self, item)
        if item.kind == "nav" then
            return {
                lines = { item.label },
                colors = { colors.yellow },
                touchAction = "nav",
                touchData = { dir = item.dir }
            }
        end

        local status = item.isActive and "ACTIVE" or "IDLE"
        return {
            lines = { item.label, status },
            colors = { colors.white, item.isActive and colors.lime or colors.gray },
            touchAction = "detail",
            touchData = item
        }
    end,

    onItemTouch = function(self, item, action)
        if action == "nav" and item and item.dir and self._types then
            local count = #self._types
            if count == 0 then return end
            if item.dir == "prev" then
                self.typeIndex = self.typeIndex - 1
                if self.typeIndex < 1 then self.typeIndex = count end
            elseif item.dir == "next" then
                self.typeIndex = self.typeIndex + 1
                if self.typeIndex > count then self.typeIndex = 1 end
            end
            self._scrollOffset = 0
            return
        end

        if action == "detail" and item and item.peripheral then
            showDetailOverlay(self, item)
        end
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Machine List", colors.white)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "No compatible machines found", colors.gray)
    end
})
