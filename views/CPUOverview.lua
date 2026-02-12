-- CPUOverview.lua
-- Displays grid overview of all AE2 crafting CPUs
-- Shows status (IDLE/BUSY) and current crafting task

local AEInterface = mpm('peripherals/AEInterface')
local GridDisplay = mpm('utils/GridDisplay')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

local module

module = {
    sleepTime = 1,

    configSchema = {
        {
            key = "showStorage",
            type = "select",
            label = "Show Storage",
            options = {
                { value = true, label = "Yes" },
                { value = false, label = "No" }
            },
            default = false
        }
    },

    new = function(monitor, config)
        config = config or {}
        local width, height = monitor.getSize()

        local self = {
            monitor = monitor,
            width = width,
            height = height,
            showStorage = config.showStorage or false,
            interface = nil,
            display = GridDisplay.new(monitor),
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

    formatCPU = function(cpuData, tasks, showStorage)
        local lines = {}
        local lineColors = {}

        -- Line 1: CPU name (truncated)
        local name = Text.truncateMiddle(cpuData.name or "Unknown", 20)
        table.insert(lines, name)
        table.insert(lineColors, colors.white)

        -- Line 2: Status
        local status = cpuData.isBusy and "BUSY" or "IDLE"
        local statusColor = cpuData.isBusy and colors.orange or colors.lime
        table.insert(lines, status)
        table.insert(lineColors, statusColor)

        -- Line 3: Crafting item (if busy)
        if cpuData.isBusy and tasks then
            local craftingItem = "..."
            for _, task in ipairs(tasks) do
                -- Match task to this CPU
                if task.cpu == cpuData.name or (not task.cpu and cpuData.isBusy) then
                    local itemName = task.name or task.item or "Unknown"
                    craftingItem = Text.prettifyName(itemName)
                    craftingItem = Text.truncateMiddle(craftingItem, 18)
                    break
                end
            end
            table.insert(lines, craftingItem)
            table.insert(lineColors, colors.yellow)
        elseif showStorage then
            -- Show storage info if not busy and config enabled
            local storageStr = (cpuData.storage or 0) .. "B"
            if cpuData.coProcessors and cpuData.coProcessors > 0 then
                storageStr = storageStr .. " " .. cpuData.coProcessors .. "cp"
            end
            table.insert(lines, storageStr)
            table.insert(lineColors, colors.gray)
        end

        return {
            lines = lines,
            colors = lineColors
        }
    end,

    render = function(self)
        if not self.initialized then
            self.monitor.clear()
            self.initialized = true
        end

        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)

        if not self.interface then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No ME Bridge", colors.red)
            return
        end

        -- Get all CPUs
        local ok, cpus = pcall(function() return self.interface:getCraftingCPUs() end)
        Yield.yield()
        if not ok or not cpus then
            MonitorHelpers.writeCentered(self.monitor, 1, "Error fetching CPUs", colors.red)
            return
        end

        -- Handle no CPUs
        if #cpus == 0 then
            self.monitor.clear()
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Crafting CPUs", colors.white)
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "No CPUs detected", colors.gray)
            return
        end

        -- Get crafting tasks (for busy CPUs)
        local tasks = nil
        local tasksOk, tasksData = pcall(function() return self.interface:getCraftingTasks() end)
        Yield.yield()
        if tasksOk and tasksData then
            tasks = tasksData
        end

        -- Draw header
        self.monitor.clear()
        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(1, 1)
        self.monitor.write("Crafting CPUs")
        self.monitor.setTextColor(colors.gray)
        local countStr = " (" .. #cpus .. ")"
        self.monitor.write(countStr)

        -- Display CPUs in grid
        local showStorage = self.showStorage
        self.display:display(cpus, function(cpu)
            return module.formatCPU(cpu, tasks, showStorage)
        end)

        self.monitor.setTextColor(colors.white)
    end
}

return module
