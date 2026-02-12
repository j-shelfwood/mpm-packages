-- CraftingQueue.lua
-- Displays all active crafting jobs across all CPUs in the AE2 network

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

return BaseView.custom({
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

    mount = function()
        local exists, pType = AEInterface.exists()
        return exists and pType == "me_bridge"
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil
        self.showCompleted = config.showCompleted or false
    end,

    getData = function(self)
        -- Get all crafting tasks
        local tasks = self.interface:getCraftingTasks()
        if not tasks then return {} end

        Yield.yield()

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

        return {
            tasks = tasks,
            busyCount = busyCount
        }
    end,

    render = function(self, data)
        local tasks = data.tasks
        local jobCount = #tasks

        -- Row 1: Header with count
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

            -- Build detail string (quantity + completion)
            local detailParts = {}
            if task.quantity then
                table.insert(detailParts, "x" .. Text.formatNumber(task.quantity, 0))
            elseif task.resource and task.resource.count then
                table.insert(detailParts, "x" .. Text.formatNumber(task.resource.count, 0))
            end
            if type(task.completion) == "number" then
                local percent = math.floor(task.completion * 100 + 0.5)
                table.insert(detailParts, percent .. "%")
            end
            local detail = #detailParts > 0 and table.concat(detailParts, " ") or nil

            -- Format: [>] Item Name - CPU Name (detail)
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
            local detailWidth = detail and (#detail + 1) or 0
            local usableWidth = math.max(0, remainingWidth - detailWidth)
            local cpuWidth = math.min(#cpuName, math.floor(usableWidth * 0.3))
            local itemWidth = math.max(0, usableWidth - cpuWidth - #separator)

            local truncatedItem = Text.truncateMiddle(itemName, itemWidth)
            local truncatedCPU = Text.truncateMiddle(cpuName, cpuWidth)

            self.monitor.write(truncatedItem)
            self.monitor.setTextColor(colors.gray)
            self.monitor.write(separator)
            self.monitor.write(truncatedCPU)

            if detail then
                self.monitor.setTextColor(colors.lightGray)
                self.monitor.write(" " .. Text.truncateMiddle(detail, detailWidth - 1))
            end

            displayedJobs = displayedJobs + 1
        end

        -- Show "..." if more jobs exist
        if jobCount > availableRows then
            MonitorHelpers.writeCentered(self.monitor, endRow, "... +" .. (jobCount - availableRows) .. " more", colors.gray)
        end

        -- Bottom row: Summary
        self.monitor.setCursorPos(1, self.height)
        self.monitor.setTextColor(colors.gray)
        local summaryText = data.busyCount .. " CPU" .. (data.busyCount ~= 1 and "s" or "") .. " busy"
        self.monitor.write(summaryText)

        self.monitor.setTextColor(colors.white)
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, 1, "Crafting Queue (0)", colors.white)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No Active Jobs", colors.gray)
        self.monitor.setCursorPos(1, self.height)
        self.monitor.setTextColor(colors.gray)
        self.monitor.write("0 CPUs busy")
    end,

    errorMessage = "Error fetching tasks"
})
