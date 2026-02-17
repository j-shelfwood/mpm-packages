-- CraftingQueue.lua
-- Displays all active crafting jobs across all CPUs in the AE2 network
-- Touch a job to see details and cancel if desired

local BaseView = mpm('views/BaseView')
local AEViewSupport = mpm('views/AEViewSupport')
local Text = mpm('utils/Text')
local Core = mpm('ui/Core')
local Yield = mpm('utils/Yield')
local ModalOverlay = mpm('ui/ModalOverlay')

-- Task detail overlay with cancel button (blocking)
local function showTaskDetail(self, task)
    local itemName = "Unknown"
    if task.resource and task.resource.displayName then
        itemName = task.resource.displayName
    elseif task.resource and task.resource.name then
        itemName = Text.prettifyName(task.resource.name)
    end

    ModalOverlay.show(self, {
        maxWidth = 32,
        maxHeight = 10,
        title = itemName,
        titleBackgroundColor = colors.orange,
        titleTextColor = colors.black,
        closeOnOutside = true,
        state = {
            statusMessage = nil,
            statusColor = colors.gray
        },
        render = function(monitor, frame, state, addAction)
            local contentY = frame.y1 + 2
            local quantity = task.quantity or (task.resource and task.resource.count) or 0

            monitor.setTextColor(colors.white)
            monitor.setCursorPos(frame.x1 + 1, contentY)
            monitor.write("Quantity: ")
            monitor.setTextColor(colors.yellow)
            monitor.write(Text.formatNumber(quantity, 0))
            contentY = contentY + 1

            if type(task.completion) == "number" then
                local percent = math.floor(task.completion * 100 + 0.5)
                monitor.setTextColor(colors.white)
                monitor.setCursorPos(frame.x1 + 1, contentY)
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

                if frame.width >= 15 then
                    contentY = contentY + 1
                    local barWidth = frame.width - 4
                    local filled = math.floor(barWidth * task.completion)
                    monitor.setCursorPos(frame.x1 + 2, contentY)
                    monitor.setBackgroundColor(progressColor)
                    monitor.write(string.rep(" ", filled))
                    monitor.setBackgroundColor(colors.lightGray)
                    monitor.write(string.rep(" ", barWidth - filled))
                    monitor.setBackgroundColor(colors.gray)
                end
            end
            contentY = contentY + 1

            if task.cpu then
                local cpuName = type(task.cpu) == "table" and task.cpu.name or tostring(task.cpu)
                monitor.setTextColor(colors.lightGray)
                monitor.setCursorPos(frame.x1 + 1, contentY)
                monitor.write("CPU: " .. Core.truncate(cpuName, frame.width - 6))
            end

            if state.statusMessage then
                monitor.setTextColor(state.statusColor)
                monitor.setCursorPos(frame.x1 + 1, frame.y2 - 2)
                monitor.write(Core.truncate(state.statusMessage, frame.width - 2))
            end

            local buttonY = frame.y2 - 1
            local cancelX = frame.x1 + 2
            monitor.setTextColor(colors.red)
            monitor.setCursorPos(cancelX, buttonY)
            monitor.write("[Cancel]")
            addAction("cancel", cancelX, buttonY, cancelX + 7, buttonY)

            local closeX = frame.x2 - 7
            monitor.setTextColor(colors.white)
            monitor.setCursorPos(closeX, buttonY)
            monitor.write("[Close]")
            addAction("close", closeX, buttonY, closeX + 6, buttonY)
        end,
        onTouch = function(monitor, frame, state, tx, ty, action)
            if action == "close" then
                return true
            end

            if action == "cancel" then
                if self.interface then
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
                            state.statusMessage = "Cancelled " .. cancelled .. " task(s)"
                            state.statusColor = colors.lime
                        else
                            state.statusMessage = "No tasks cancelled"
                            state.statusColor = colors.orange
                        end
                    else
                        state.statusMessage = "Cancel failed"
                        state.statusColor = colors.red
                    end
                else
                    state.statusMessage = "No ME Bridge"
                    state.statusColor = colors.red
                end
            end
            return false
        end
    })
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
            return AEViewSupport.mount()
        end,

    init = function(self, config)
        AEViewSupport.init(self)
        self.showCompleted = config.showCompleted or false
        self.busyCount = 0
        self.totalCPUs = 0
    end,

    getData = function(self)
        -- Lazy re-init: retry if host not yet discovered at init time
        if not AEViewSupport.ensureInterface(self) then return nil end

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
