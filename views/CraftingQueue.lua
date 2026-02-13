-- CraftingQueue.lua
-- Displays all active crafting jobs across all CPUs in the AE2 network
-- Touch a job to see details and cancel if desired

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local Core = mpm('ui/Core')
local Yield = mpm('utils/Yield')

-- Task detail overlay with cancel button (blocking)
local function showTaskDetail(self, task)
    local monitor = self.monitor
    local width, height = monitor.getSize()

    -- Calculate overlay bounds
    local overlayWidth = math.min(width - 2, 32)
    local overlayHeight = math.min(height - 2, 10)
    local x1 = math.floor((width - overlayWidth) / 2) + 1
    local y1 = math.floor((height - overlayHeight) / 2) + 1
    local x2 = x1 + overlayWidth - 1
    local y2 = y1 + overlayHeight - 1

    local monitorName = self.peripheralName
    local statusMessage = nil
    local statusColor = colors.gray

    while true do
        -- Draw background
        monitor.setBackgroundColor(colors.gray)
        for y = y1, y2 do
            monitor.setCursorPos(x1, y)
            monitor.write(string.rep(" ", overlayWidth))
        end

        -- Title bar
        local itemName = "Unknown"
        if task.resource and task.resource.displayName then
            itemName = task.resource.displayName
        elseif task.resource and task.resource.name then
            itemName = Text.prettifyName(task.resource.name)
        end

        monitor.setBackgroundColor(colors.orange)
        monitor.setTextColor(colors.black)
        monitor.setCursorPos(x1, y1)
        monitor.write(string.rep(" ", overlayWidth))
        monitor.setCursorPos(x1 + 1, y1)
        monitor.write(Core.truncate(itemName, overlayWidth - 2))

        -- Content
        monitor.setBackgroundColor(colors.gray)
        local contentY = y1 + 2

        -- Quantity
        local quantity = task.quantity or (task.resource and task.resource.count) or 0
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.write("Quantity: ")
        monitor.setTextColor(colors.yellow)
        monitor.write(Text.formatNumber(quantity, 0))
        contentY = contentY + 1

        -- Progress
        if type(task.completion) == "number" then
            local percent = math.floor(task.completion * 100 + 0.5)
            monitor.setTextColor(colors.white)
            monitor.setCursorPos(x1 + 1, contentY)
            monitor.write("Progress: ")

            local progressColor = colors.orange
            if percent >= 75 then
                progressColor = colors.lime
            elseif percent >= 50 then
                progressColor = colors.yellow
            end
            monitor.setTextColor(progressColor)
            monitor.write(percent .. "%")
            contentY = contentY + 1

            -- Progress bar
            if overlayWidth >= 15 then
                contentY = contentY + 1
                local barWidth = overlayWidth - 4
                local filled = math.floor(barWidth * task.completion)
                monitor.setCursorPos(x1 + 2, contentY)
                monitor.setBackgroundColor(progressColor)
                monitor.write(string.rep(" ", filled))
                monitor.setBackgroundColor(colors.lightGray)
                monitor.write(string.rep(" ", barWidth - filled))
                monitor.setBackgroundColor(colors.gray)
            end
        end
        contentY = contentY + 1

        -- CPU name
        if task.cpu then
            local cpuName = type(task.cpu) == "table" and task.cpu.name or tostring(task.cpu)
            monitor.setTextColor(colors.lightGray)
            monitor.setCursorPos(x1 + 1, contentY)
            monitor.write("CPU: " .. Core.truncate(cpuName, overlayWidth - 6))
        end

        -- Status message
        if statusMessage then
            monitor.setBackgroundColor(colors.gray)
            monitor.setTextColor(statusColor)
            monitor.setCursorPos(x1 + 1, y2 - 2)
            monitor.write(Core.truncate(statusMessage, overlayWidth - 2))
        end

        -- Action buttons
        local buttonY = y2 - 1
        monitor.setBackgroundColor(colors.gray)

        -- Cancel button
        monitor.setTextColor(colors.red)
        monitor.setCursorPos(x1 + 2, buttonY)
        monitor.write("[Cancel]")

        -- Close button
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(x2 - 7, buttonY)
        monitor.write("[Close]")

        Core.resetColors(monitor)

        -- Wait for touch
        local event, side, tx, ty = os.pullEvent("monitor_touch")

        if side == monitorName then
            -- Close button or outside overlay
            if (ty == buttonY and tx >= x2 - 7 and tx <= x2 - 1) or
               tx < x1 or tx > x2 or ty < y1 or ty > y2 then
                return
            end

            -- Cancel button
            if ty == buttonY and tx >= x1 + 2 and tx <= x1 + 9 then
                if self.interface then
                    -- Build filter for cancellation
                    local filter = {}
                    if task.resource and task.resource.name then
                        filter.name = task.resource.name
                    end

                    local ok, result = pcall(function()
                        return self.interface:cancelCraftingTasks(filter)
                    end)

                    if ok then
                        local cancelled = result or 0
                        if cancelled > 0 then
                            statusMessage = "Cancelled " .. cancelled .. " task(s)"
                            statusColor = colors.lime
                        else
                            statusMessage = "No tasks cancelled"
                            statusColor = colors.orange
                        end
                    else
                        statusMessage = "Cancel failed"
                        statusColor = colors.red
                    end
                else
                    statusMessage = "No ME Bridge"
                    statusColor = colors.red
                end
            end
        end
    end
end

return BaseView.interactive({
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
        self.busyCount = 0
        self.totalCPUs = 0
    end,

    getData = function(self)
        if not self.interface then return nil end

        -- Get all crafting tasks
        local tasks = self.interface:getCraftingTasks()
        if not tasks then return {} end

        Yield.yield()

        -- Get CPU status for summary
        local cpusOk, cpus = pcall(function() return self.interface:getCraftingCPUs() end)
        Yield.yield()

        self.busyCount = 0
        self.totalCPUs = 0
        if cpusOk and cpus then
            self.totalCPUs = #cpus
            for _, cpu in ipairs(cpus) do
                if cpu.isBusy then
                    self.busyCount = self.busyCount + 1
                end
            end
        end

        return tasks
    end,

    header = function(self, data)
        return {
            text = "CRAFTING",
            color = colors.orange,
            secondary = " (" .. #data .. " jobs)",
            secondaryColor = colors.gray
        }
    end,

    formatItem = function(self, task)
        -- Extract item name
        local itemName = "Unknown"
        if task.resource and task.resource.displayName then
            itemName = task.resource.displayName
        elseif task.resource and task.resource.name then
            itemName = Text.prettifyName(task.resource.name)
        end

        -- Build detail string
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
        local detail = #detailParts > 0 and table.concat(detailParts, " ") or ""

        -- Status color
        local statusColor = colors.orange
        if task.completion then
            if task.completion >= 0.99 then
                statusColor = colors.lime
            elseif task.completion >= 0.75 then
                statusColor = colors.yellow
            end
        end

        return {
            lines = { itemName, detail },
            colors = { colors.white, statusColor },
            touchAction = "detail",
            touchData = task
        }
    end,

    onItemTouch = function(self, task, action)
        showTaskDetail(self, task)
    end,

    footer = function(self, data)
        local footerText = self.busyCount .. "/" .. self.totalCPUs .. " CPUs busy"
        return {
            text = footerText,
            color = colors.gray
        }
    end,

    emptyMessage = "No active crafting jobs"
})
