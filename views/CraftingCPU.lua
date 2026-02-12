-- CraftingCPU.lua
-- Displays status of a single AE2 crafting CPU
-- Configurable: which CPU to monitor

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

-- Get available CPUs for config picker
local function getCPUOptions()
    local ok, exists = pcall(AEInterface.exists)
    if not ok or not exists then return {} end

    local okNew, interface = pcall(AEInterface.new)
    if not okNew or not interface then return {} end

    local cpusOk, cpus = pcall(function() return interface:getCraftingCPUs() end)
    if not cpusOk or not cpus then return {} end

    local options = {}
    for _, cpu in ipairs(cpus) do
        table.insert(options, {
            value = cpu.name,
            label = cpu.name .. " (" .. (cpu.storage or 0) .. "B)"
        })
    end

    return options
end

return BaseView.custom({
    sleepTime = 1,

    configSchema = {
        {
            key = "cpu",
            type = "select",
            label = "Crafting CPU",
            options = getCPUOptions,
            default = nil,
            required = true
        }
    },

    mount = function()
        local exists, pType = AEInterface.exists()
        return exists and pType == "me_bridge"
    end,

    init = function(self, config)
        self.interface = AEInterface.new()
        self.cpuName = config.cpu
    end,

    getData = function(self)
        if not self.cpuName then
            return nil
        end

        -- Get all CPUs and find ours
        local cpus = self.interface:getCraftingCPUs()
        if not cpus then return nil end

        Yield.yield()

        local cpu = nil
        for _, c in ipairs(cpus) do
            if c.name == self.cpuName then
                cpu = c
                break
            end
        end

        if not cpu then
            return { notFound = true }
        end

        -- Get crafting task info if busy
        local currentTask = nil
        if cpu.isBusy then
            local tasksOk, tasks = pcall(function() return self.interface:getCraftingTasks() end)
            Yield.yield()
            if tasksOk and tasks then
                for _, task in ipairs(tasks) do
                    -- Find task matching this CPU (task.cpu matches cpu.name)
                    if task.cpu == cpu.name or (not task.cpu and cpu.isBusy) then
                        currentTask = task
                        break
                    end
                end
            end
        end

        return {
            cpu = cpu,
            currentTask = currentTask
        }
    end,

    render = function(self, data)
        if data.notFound then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "CPU not found", colors.red)
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, self.cpuName, colors.gray)
            return
        end

        local cpu = data.cpu

        -- Row 1: CPU name
        local name = Text.truncateMiddle(cpu.name, self.width)
        MonitorHelpers.writeCentered(self.monitor, 1, name, colors.white)

        -- Center area: Status
        local centerY = math.floor(self.height / 2)

        if cpu.isBusy then
            -- Show BUSY status
            MonitorHelpers.writeCentered(self.monitor, centerY - 1, "CRAFTING", colors.orange)

            -- Show current task info
            if data.currentTask then
                local itemName = data.currentTask.name or data.currentTask.item or "Unknown"
                itemName = Text.prettifyName(itemName)
                itemName = Text.truncateMiddle(itemName, self.width - 2)
                MonitorHelpers.writeCentered(self.monitor, centerY + 1, itemName, colors.yellow)
            end
        else
            -- Show IDLE status
            MonitorHelpers.writeCentered(self.monitor, centerY, "IDLE", colors.lime)
        end

        -- Bottom: Storage info
        self.monitor.setTextColor(colors.gray)
        local storageStr = (cpu.storage or 0) .. "B storage"
        if cpu.coProcessors and cpu.coProcessors > 0 then
            storageStr = storageStr .. " | " .. cpu.coProcessors .. " co-proc"
        end
        storageStr = Text.truncateMiddle(storageStr, self.width)
        self.monitor.setCursorPos(1, self.height)
        self.monitor.write(storageStr)

        self.monitor.setTextColor(colors.white)
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Crafting CPU", colors.white)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Configure to select CPU", colors.gray)
    end,

    errorMessage = "Error fetching CPUs"
})
