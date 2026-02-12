-- CraftingQueue.lua
-- Displays all active crafting jobs across all CPUs in the AE2 network

local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

local module = {
    sleepTime = 1,

    configSchema = {
        {
            key = "showCompleted",
            type = "select",
            label = "Show Completed",
            options = {
                { value = false, label = "No" },
                { value = true, label = "Yes (brief)" }
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
            showCompleted = config.showCompleted or false,
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

        -- Get all crafting tasks
        local ok, tasks = pcall(function() return self.interface:getCraftingTasks() end)
        Yield.yield()
        if not ok or not tasks then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "Error fetching tasks", colors.red)
            return
        end

        -- Get CPU status for summary
        local cpusOk, cpus = pcall(function() return self.interface:getCraftingCPUs() end)
        Yield.yield()
        local busyCount = 0
        if cpusOk and cpus then
            for _, cpu in ipairs(cpus) do
                if cpu.isBusy then
                    busyCount = busyCount + 1
                end
            end
        end

        -- Clear screen
        self.monitor.clear()

        -- Row 1: Header with count
        local jobCount = #tasks
        local headerText = "Crafting Queue (" .. jobCount .. ")"
        MonitorHelpers.writeCentered(self.monitor, 1, headerText, colors.white)

        -- Handle empty queue
        if jobCount == 0 then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No Active Jobs", colors.gray)
            -- Bottom row: Summary
            self.monitor.setCursorPos(1, self.height)
            self.monitor.setTextColor(colors.gray)
            self.monitor.write("0 CPUs busy")
            return
        end

        -- Calculate available rows for job list (header + jobs + footer)
        local startRow = 2
        local endRow = self.height - 1
        local availableRows = endRow - startRow + 1

        -- Render jobs (scrollable if needed)
        local displayedJobs = 0
        for i, task in ipairs(tasks) do
            if i > availableRows then
                break  -- No more room to display
            end

            local row = startRow + i - 1

            -- Extract task info
            -- Task structure from Java: {resource={...}, quantity=N, cpu={...}, completion=0.5, ...}
            local itemName = "Unknown"
            if task.resource and task.resource.displayName then
                itemName = task.resource.displayName
            elseif task.resource and task.resource.name then
                itemName = Text.prettifyName(task.resource.name)
            end

            local cpuName = "Unknown CPU"
            if task.cpu and task.cpu.name then
                cpuName = task.cpu.name
            end

            -- Status indicator based on completion
            local status = ">"
            local statusColor = colors.orange
            if task.completion then
                if task.completion >= 0.99 then
                    status = "!"
                    statusColor = colors.lime
                elseif task.completion >= 0.75 then
                    status = "="
                    statusColor = colors.yellow
                end
            end

            -- Format: [>] Item Name - CPU Name
            self.monitor.setCursorPos(1, row)
            
            -- Status indicator
            self.monitor.setTextColor(statusColor)
            self.monitor.write("[" .. status .. "]")
            
            -- Item name
            self.monitor.setTextColor(colors.white)
            self.monitor.write(" ")
            
            -- Calculate remaining width for item and CPU name
            local remainingWidth = self.width - 4  -- minus "[>] "
            local separator = " - "
            local cpuWidth = math.min(#cpuName, math.floor(remainingWidth * 0.3))
            local itemWidth = remainingWidth - cpuWidth - #separator
            
            local truncatedItem = Text.truncateMiddle(itemName, itemWidth)
            local truncatedCPU = Text.truncateMiddle(cpuName, cpuWidth)
            
            self.monitor.write(truncatedItem)
            self.monitor.setTextColor(colors.gray)
            self.monitor.write(separator)
            self.monitor.write(truncatedCPU)

            displayedJobs = displayedJobs + 1
        end

        -- Show "..." if more jobs exist
        if jobCount > availableRows then
            self.monitor.setCursorPos(1, endRow)
            self.monitor.setTextColor(colors.gray)
            MonitorHelpers.writeCentered(self.monitor, endRow, "... +" .. (jobCount - availableRows) .. " more", colors.gray)
        end

        -- Bottom row: Summary
        self.monitor.setCursorPos(1, self.height)
        self.monitor.setTextColor(colors.gray)
        local summaryText = busyCount .. " CPU" .. (busyCount ~= 1 and "s" or "") .. " busy"
        self.monitor.write(summaryText)

        self.monitor.setTextColor(colors.white)
    end
}

return module
