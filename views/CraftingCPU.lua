-- CraftingCPU.lua
-- Displays status of a single AE2 crafting CPU
-- Configurable: which CPU to monitor

local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')

-- Get available CPUs for config picker
local function getCPUOptions()
    local ok, exists = pcall(AEInterface.exists)
    if not ok or not exists then return {} end

    local okNew, interface = pcall(AEInterface.new)
    if not okNew or not interface then return {} end

    local cpusOk, cpus = pcall(AEInterface.getCraftingCPUs, interface)
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

local module

module = {
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

    new = function(monitor, config)
        config = config or {}
        local width, height = monitor.getSize()

        local self = {
            monitor = monitor,
            width = width,
            height = height,
            cpuName = config.cpu,
            interface = nil,
            initialized = false
        }

        local ok, interface = pcall(AEInterface.new)
        if ok and interface then
            self.interface = interface
        end

        return self
    end,

    mount = function()
        local exists, pType = AEInterface.exists()
        return exists and pType == "me_bridge"
    end,

    render = function(self)
        if not self.initialized then
            self.monitor.clear()
            self.initialized = true
        end

        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)

        -- Check interface
        if not self.interface then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No ME Bridge", colors.red)
            return
        end

        -- Check if CPU is configured
        if not self.cpuName then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Crafting CPU", colors.white)
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Configure to select CPU", colors.gray)
            return
        end

        -- Get all CPUs and find ours
        local ok, cpus = pcall(AEInterface.getCraftingCPUs, self.interface)
        if not ok or not cpus then
            MonitorHelpers.writeCentered(self.monitor, 1, "Error fetching CPUs", colors.red)
            return
        end

        local cpu = nil
        for _, c in ipairs(cpus) do
            if c.name == self.cpuName then
                cpu = c
                break
            end
        end

        if not cpu then
            self.monitor.clear()
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "CPU not found", colors.red)
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, self.cpuName, colors.gray)
            return
        end

        -- Clear screen
        self.monitor.clear()

        -- Row 1: CPU name
        local name = Text.truncateMiddle(cpu.name, self.width)
        MonitorHelpers.writeCentered(self.monitor, 1, name, colors.white)

        -- Center area: Status
        local centerY = math.floor(self.height / 2)

        if cpu.isBusy then
            -- Show BUSY status
            MonitorHelpers.writeCentered(self.monitor, centerY - 1, "CRAFTING", colors.orange)

            -- Try to get current task info
            local tasksOk, tasks = pcall(AEInterface.getCraftingTasks, self.interface)
            if tasksOk and tasks then
                for _, task in ipairs(tasks) do
                    -- Find task matching this CPU (task.cpu matches cpu.name)
                    if task.cpu == cpu.name or (not task.cpu and cpu.isBusy) then
                        local itemName = task.name or task.item or "Unknown"
                        itemName = Text.prettifyName(itemName)
                        itemName = Text.truncateMiddle(itemName, self.width - 2)
                        MonitorHelpers.writeCentered(self.monitor, centerY + 1, itemName, colors.yellow)
                        break
                    end
                end
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
    end
}

return module
