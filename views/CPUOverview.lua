-- CPUOverview.lua
-- Displays grid overview of all AE2 crafting CPUs
-- Shows status (IDLE/BUSY) and current crafting task

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')

return BaseView.grid({
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

    mount = function()
        local exists, pType = AEInterface.exists()
        return exists and pType == "me_bridge"
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil
        self.showStorage = config.showStorage or false
        self.tasks = nil  -- Will be populated by getData
    end,

    getData = function(self)
        -- Lazy re-init: retry if host not yet discovered at init time
        if not self.interface then
            local ok, interface = pcall(AEInterface.new)
            self.interface = ok and interface or nil
        end
        if not self.interface then return nil end

        -- Get all CPUs
        local cpus = self.interface:getCraftingCPUs()
        if not cpus then return {} end

        -- Get crafting tasks (for busy CPUs)
        local tasksOk, tasksData = pcall(function()
            return self.interface:getCraftingTasks()
        end)
        self.tasks = tasksOk and tasksData or nil

        return cpus
    end,

    header = function(self, data)
        return {
            text = "Crafting CPUs",
            color = colors.white,
            secondary = " (" .. #data .. ")",
            secondaryColor = colors.gray
        }
    end,

    cellHeight = 3,

    formatItem = function(self, cpuData)
        local lines = {}
        local lineColors = {}
        local taskInfo = nil

        -- Line 1: CPU name
        local name = cpuData.name or "Unknown"

        -- Line 2: Status
        local status = cpuData.isBusy and "BUSY" or "IDLE"
        local statusColor = cpuData.isBusy and colors.orange or colors.lime

        table.insert(lines, name)
        table.insert(lineColors, colors.white)
        table.insert(lines, status)
        table.insert(lineColors, statusColor)

        -- Line 3: Crafting item (if busy) or storage info
        if cpuData.isBusy and self.tasks then
            local craftingItem = "..."
            for _, task in ipairs(self.tasks) do
                if task.cpu == cpuData.name or (not task.cpu and cpuData.isBusy) then
                    local itemName = "Unknown"
                    if task.resource and task.resource.displayName then
                        itemName = task.resource.displayName
                    elseif task.resource and task.resource.name then
                        itemName = Text.prettifyName(task.resource.name)
                    elseif task.name or task.item then
                        itemName = Text.prettifyName(task.name or task.item)
                    end
                    craftingItem = itemName
                    taskInfo = task
                    break
                end
            end

            -- Add crafting item with optional progress
            local detailStr = craftingItem
            if taskInfo then
                local quantity = taskInfo.quantity or (taskInfo.resource and taskInfo.resource.count)
                if quantity then
                    detailStr = detailStr .. " x" .. Text.formatNumber(quantity, 0)
                end
                if type(taskInfo.completion) == "number" then
                    detailStr = detailStr .. " " .. math.floor(taskInfo.completion * 100 + 0.5) .. "%"
                end
            end
            table.insert(lines, detailStr)
            table.insert(lineColors, colors.yellow)
        elseif self.showStorage then
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

    emptyMessage = "No CPUs detected",
    maxItems = 50
})
