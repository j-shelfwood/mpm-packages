-- NetworkDashboard.lua
-- Single-screen ME network overview combining key metrics
-- Shows: Connection status, Energy, Storage, CPU status, Active crafting count
-- Designed for at-a-glance monitoring on smaller monitors

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')

-- Draw a horizontal progress bar
local function drawProgressBar(monitor, x, y, width, percent, fillColor, emptyColor)
    local filled = math.floor(width * math.min(1, math.max(0, percent)))
    local empty = width - filled

    monitor.setCursorPos(x, y)
    monitor.setBackgroundColor(fillColor)
    monitor.write(string.rep(" ", filled))
    monitor.setBackgroundColor(emptyColor)
    monitor.write(string.rep(" ", empty))
    monitor.setBackgroundColor(colors.black)
end

-- Get color based on percentage (green -> yellow -> red)
local function getPercentColor(percent)
    if percent < 0.7 then
        return colors.lime
    elseif percent < 0.9 then
        return colors.yellow
    else
        return colors.red
    end
end

-- Detailed mode render
local function renderDetailed(self, data)
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
    local energyColor = getPercentColor(1 - energyPercent)  -- Invert: low energy is bad

    self.monitor.setCursorPos(1, y)
    self.monitor.setTextColor(colors.white)
    self.monitor.write("Energy ")
    self.monitor.setTextColor(energyColor)
    self.monitor.write(Text.formatNumber(data.energyStored, 0))
    self.monitor.setTextColor(colors.gray)
    self.monitor.write("/" .. Text.formatNumber(data.energyCapacity, 0))
    y = y + 1

    if self.width >= 15 then
        drawProgressBar(self.monitor, 1, y, self.width, energyPercent, energyColor, colors.gray)
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
    local storageColor = getPercentColor(storagePercent)

    self.monitor.setCursorPos(1, y)
    self.monitor.setTextColor(colors.white)
    self.monitor.write("Items ")
    self.monitor.setTextColor(storageColor)
    self.monitor.write(Text.formatNumber(data.itemsUsed, 0))
    self.monitor.setTextColor(colors.gray)
    self.monitor.write("/" .. Text.formatNumber(data.itemsTotal, 0))
    y = y + 1

    if self.width >= 15 then
        drawProgressBar(self.monitor, 1, y, self.width, storagePercent, storageColor, colors.gray)
        y = y + 1
    end

    -- Fluid storage (compact)
    local fluidPercent = data.fluidsTotal > 0 and (data.fluidsUsed / data.fluidsTotal) or 0
    local fluidColor = getPercentColor(fluidPercent)

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
local function renderCompact(self, data)
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
    local storageColor = getPercentColor(storagePercent / 100)
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

return BaseView.custom({
    sleepTime = 2,

    configSchema = {
        {
            key = "displayMode",
            type = "select",
            label = "Display Mode",
            options = {
                { value = "detailed", label = "Detailed" },
                { value = "compact", label = "Compact" }
            },
            default = "detailed"
        }
    },

    mount = function()
        return AEInterface.exists()
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil
        self.displayMode = config.displayMode or "detailed"
    end,

    getData = function(self)
        if not self.interface then return nil end

        local data = {}

        -- Connection status
        local connOk, isConnected = pcall(function()
            return self.interface:isConnected()
        end)
        data.isConnected = connOk and isConnected or false

        local onlineOk, isOnline = pcall(function()
            return self.interface:isOnline()
        end)
        data.isOnline = onlineOk and isOnline or false

        -- Energy stats
        local energy = self.interface:energy()
        data.energyStored = energy.stored or 0
        data.energyCapacity = energy.capacity or 0
        data.energyUsage = energy.usage or 0

        -- Energy input rate
        local inputOk, energyInput = pcall(function()
            return self.interface:getAverageEnergyInput()
        end)
        data.energyInput = inputOk and energyInput or 0

        -- Item storage
        local itemStorage = self.interface:itemStorage()
        data.itemsUsed = itemStorage.used or 0
        data.itemsTotal = itemStorage.total or 0

        -- Fluid storage
        local fluidStorage = self.interface:fluidStorage()
        data.fluidsUsed = fluidStorage.used or 0
        data.fluidsTotal = fluidStorage.total or 0

        -- CPU status
        local cpus = self.interface:getCraftingCPUs()
        data.cpuTotal = #cpus
        data.cpuBusy = 0
        for _, cpu in ipairs(cpus) do
            if cpu.isBusy then
                data.cpuBusy = data.cpuBusy + 1
            end
        end

        -- Active crafting tasks
        local tasks = self.interface:getCraftingTasks()
        data.activeCrafts = #tasks

        return data
    end,

    render = function(self, data)
        if self.displayMode == "compact" then
            renderCompact(self, data)
        else
            renderDetailed(self, data)
        end
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No ME Network", colors.red)
    end,

    emptyMessage = "No ME Network",
    errorMessage = "Dashboard Error"
})
