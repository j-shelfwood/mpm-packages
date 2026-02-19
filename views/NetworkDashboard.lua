-- NetworkDashboard.lua
-- Single-screen ME network overview combining key metrics
-- Shows: Connection status, Energy, Storage, CPU status, Active crafting count
-- Designed for at-a-glance monitoring on smaller monitors
--
-- Split module:
--   NetworkDashboardRenderers.lua - Render modes (detailed, compact)

local BaseView = mpm('views/BaseView')
local AEViewSupport = mpm('views/AEViewSupport')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Renderers = mpm('views/NetworkDashboardRenderers')

local function countCPUCraftingJobs(cpus)
    local count = 0
    for _, cpu in ipairs(cpus or {}) do
        if cpu.isBusy and type(cpu.craftingJob) == "table" then
            count = count + 1
        end
    end
    return count
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
            return AEViewSupport.mount()
        end,

    init = function(self, config)
        AEViewSupport.init(self)
        self.displayMode = config.displayMode or "detailed"
    end,

    getData = function(self)
        -- Lazy re-init: retry if host not yet discovered at init time
        if not AEViewSupport.ensureInterface(self) then return nil end

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
        local tasksOk, tasks = pcall(function()
            return self.interface:getCraftingTasks()
        end)
        tasks = (tasksOk and type(tasks) == "table") and tasks or {}
        local fallbackCount = countCPUCraftingJobs(cpus)
        data.activeCrafts = math.max(#tasks, fallbackCount)

        return data
    end,

    render = function(self, data)
        if self.displayMode == "compact" then
            Renderers.renderCompact(self, data)
        else
            Renderers.renderDetailed(self, data)
        end
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No ME Network", colors.red)
    end,

    emptyMessage = "No ME Network",
    errorMessage = "Dashboard Error"
})
