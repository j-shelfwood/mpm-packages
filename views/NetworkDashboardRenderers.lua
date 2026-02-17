-- NetworkDashboardRenderers.lua
-- Render modes for NetworkDashboard (detailed, compact)
-- Extracted from NetworkDashboard.lua for maintainability

local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')

local Renderers = {}

-- Draw a horizontal progress bar
function Renderers.drawProgressBar(monitor, x, y, width, percent, fillColor, emptyColor)
    MonitorHelpers.drawProgressBar(monitor, x, y, width, percent * 100, fillColor, emptyColor, false)
end

-- Get color based on percentage (green -> yellow -> red)
function Renderers.getPercentColor(percent)
    if percent < 0.7 then
        return colors.lime
    elseif percent < 0.9 then
        return colors.yellow
    else
        return colors.red
    end
end

-- Detailed mode render
function Renderers.renderDetailed(self, data)
    local y = 1

    -- Title with connection status
    self.monitor.setCursorPos(1, y)
    self.monitor.setTextColor(colors.cyan)
    self.monitor.write("ME NETWORK")

    -- Connection indicator
    local connStr, connColor
    if data.isConnected and data.isOnline then
        connStr = "[OK]"
        connColor = colors.lime
    elseif data.isConnected then
        connStr = "[BOOT]"
        connColor = colors.yellow
    else
        connStr = "[OFF]"
        connColor = colors.red
    end
    self.monitor.setTextColor(connColor)
    self.monitor.setCursorPos(self.width - #connStr + 1, y)
    self.monitor.write(connStr)
    y = y + 1

    -- Separator
    self.monitor.setTextColor(colors.gray)
    self.monitor.setCursorPos(1, y)
    self.monitor.write(string.rep("-", self.width))
    y = y + 1

    -- Energy section
    local energyPercent = data.energyCapacity > 0 and (data.energyStored / data.energyCapacity) or 0
    local energyColor = Renderers.getPercentColor(1 - energyPercent)  -- Invert: low energy is bad

    self.monitor.setCursorPos(1, y)
    self.monitor.setTextColor(colors.white)
    self.monitor.write("Energy ")
    self.monitor.setTextColor(energyColor)
    self.monitor.write(Text.formatNumber(data.energyStored, 0))
    self.monitor.setTextColor(colors.gray)
    self.monitor.write("/" .. Text.formatNumber(data.energyCapacity, 0))
    y = y + 1

    if self.width >= 15 then
        Renderers.drawProgressBar(self.monitor, 1, y, self.width, energyPercent, energyColor, colors.gray)
        y = y + 1
    end

    -- Energy flow indicator
    self.monitor.setCursorPos(1, y)
    local netFlow = data.energyInput - data.energyUsage
    if netFlow >= 0 then
        self.monitor.setTextColor(colors.lime)
        self.monitor.write("+" .. Text.formatNumber(netFlow, 0))
    else
        self.monitor.setTextColor(colors.red)
        self.monitor.write(Text.formatNumber(netFlow, 0))
    end
    self.monitor.setTextColor(colors.gray)
    self.monitor.write(" AE/t")
    y = y + 2

    -- Storage section
    local storagePercent = data.itemsTotal > 0 and (data.itemsUsed / data.itemsTotal) or 0
    local storageColor = Renderers.getPercentColor(storagePercent)

    self.monitor.setCursorPos(1, y)
    self.monitor.setTextColor(colors.white)
    self.monitor.write("Items ")
    self.monitor.setTextColor(storageColor)
    self.monitor.write(Text.formatNumber(data.itemsUsed, 0))
    self.monitor.setTextColor(colors.gray)
    self.monitor.write("/" .. Text.formatNumber(data.itemsTotal, 0))
    y = y + 1

    if self.width >= 15 then
        Renderers.drawProgressBar(self.monitor, 1, y, self.width, storagePercent, storageColor, colors.gray)
        y = y + 1
    end

    -- Fluid storage (compact)
    local fluidPercent = data.fluidsTotal > 0 and (data.fluidsUsed / data.fluidsTotal) or 0
    local fluidColor = Renderers.getPercentColor(fluidPercent)

    self.monitor.setCursorPos(1, y)
    self.monitor.setTextColor(colors.white)
    self.monitor.write("Fluids ")
    self.monitor.setTextColor(fluidColor)
    self.monitor.write(math.floor(fluidPercent * 100) .. "%")
    y = y + 2

    -- CPU section
    self.monitor.setCursorPos(1, y)
    self.monitor.setTextColor(colors.white)
    self.monitor.write("CPUs ")

    local cpuColor = colors.lime
    if data.cpuBusy == data.cpuTotal and data.cpuTotal > 0 then
        cpuColor = colors.red
    elseif data.cpuBusy > 0 then
        cpuColor = colors.yellow
    end

    self.monitor.setTextColor(cpuColor)
    self.monitor.write(data.cpuBusy)
    self.monitor.setTextColor(colors.gray)
    self.monitor.write("/" .. data.cpuTotal .. " busy")
    y = y + 1

    -- Active crafts
    self.monitor.setCursorPos(1, y)
    self.monitor.setTextColor(colors.white)
    self.monitor.write("Crafting ")

    local craftColor = data.activeCrafts > 0 and colors.yellow or colors.lime
    self.monitor.setTextColor(craftColor)
    self.monitor.write(tostring(data.activeCrafts))
    self.monitor.setTextColor(colors.gray)
    self.monitor.write(" active")

    self.monitor.setTextColor(colors.white)
end

-- Compact mode render
function Renderers.renderCompact(self, data)
    local y = 1

    -- Title with connection status indicator
    self.monitor.setCursorPos(1, y)
    self.monitor.setTextColor(colors.cyan)
    self.monitor.write("ME")

    local connColor = (data.isConnected and data.isOnline) and colors.lime or colors.red
    self.monitor.setTextColor(connColor)
    self.monitor.write(" *")

    -- Energy percentage
    local energyPercent = data.energyCapacity > 0 and (data.energyStored / data.energyCapacity * 100) or 0
    local energyColor = energyPercent < 25 and colors.red or (energyPercent < 50 and colors.yellow or colors.lime)
    local energyStr = math.floor(energyPercent) .. "%"
    self.monitor.setTextColor(energyColor)
    self.monitor.setCursorPos(self.width - #energyStr + 1, y)
    self.monitor.write(energyStr)
    y = y + 1

    -- Storage percentage
    local storagePercent = data.itemsTotal > 0 and (data.itemsUsed / data.itemsTotal * 100) or 0
    local storageColor = Renderers.getPercentColor(storagePercent / 100)
    self.monitor.setCursorPos(1, y)
    self.monitor.setTextColor(colors.white)
    self.monitor.write("Stor ")
    self.monitor.setTextColor(storageColor)
    self.monitor.write(math.floor(storagePercent) .. "%")
    y = y + 1

    -- CPU status
    self.monitor.setCursorPos(1, y)
    self.monitor.setTextColor(colors.white)
    self.monitor.write("CPU ")
    local cpuColor = data.cpuBusy == data.cpuTotal and data.cpuTotal > 0 and colors.red or colors.lime
    self.monitor.setTextColor(cpuColor)
    self.monitor.write(data.cpuBusy .. "/" .. data.cpuTotal)
    y = y + 1

    -- Crafting
    if data.activeCrafts > 0 then
        self.monitor.setCursorPos(1, y)
        self.monitor.setTextColor(colors.yellow)
        self.monitor.write("Craft " .. data.activeCrafts)
    end

    self.monitor.setTextColor(colors.white)
end

return Renderers
