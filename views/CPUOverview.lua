-- CPUOverview.lua
-- Displays grid overview of all AE2 crafting CPUs
-- Shows compact CPU labels and current crafting task on 2-line cells

local BaseView = mpm('views/BaseView')
local AEViewSupport = mpm('views/AEViewSupport')
local Text = mpm('utils/Text')

local function getTaskCpuName(task)
    if not task or not task.cpu then return nil end
    if type(task.cpu) == "table" then
        return task.cpu.name
    end
    return tostring(task.cpu)
end

local function getCraftingItemLabel(task)
    if not task then
        return "BUSY"
    end

    local itemName = "Crafting"
    if task.resource and task.resource.displayName then
        itemName = task.resource.displayName
    elseif task.resource and task.resource.name then
        itemName = Text.prettifyName(task.resource.name)
    elseif task.name or task.item then
        itemName = Text.prettifyName(task.name or task.item)
    end

    if type(task.completion) == "number" then
        local percent = math.floor(task.completion * 100 + 0.5)
        itemName = itemName .. " " .. percent .. "%"
    end

    return itemName
end

local function buildTaskMap(cpus, tasks)
    local map = {}
    local usedTasks = {}
    local nameToIndexes = {}

    for index, cpu in ipairs(cpus or {}) do
        if cpu.name and cpu.name ~= "" then
            nameToIndexes[cpu.name] = nameToIndexes[cpu.name] or {}
            table.insert(nameToIndexes[cpu.name], index)
        end
    end

    for taskIndex, task in ipairs(tasks or {}) do
        local taskCpuName = getTaskCpuName(task)
        local indexes = taskCpuName and nameToIndexes[taskCpuName] or nil
        if indexes and #indexes == 1 then
            local idx = indexes[1]
            if cpus[idx] and cpus[idx].isBusy and not map[idx] then
                map[idx] = task
                usedTasks[taskIndex] = true
            end
        end
    end

    local remainingTasks = {}
    for taskIndex, task in ipairs(tasks or {}) do
        if not usedTasks[taskIndex] then
            table.insert(remainingTasks, task)
        end
    end

    local cursor = 1
    for cpuIndex, cpu in ipairs(cpus or {}) do
        if cpu.isBusy and not map[cpuIndex] then
            map[cpuIndex] = remainingTasks[cursor]
            cursor = cursor + 1
        end
    end

    return map
end

local function buildTasksFromCPUJobs(cpus)
    local derived = {}
    for index, cpu in ipairs(cpus or {}) do
        if cpu.isBusy and type(cpu.craftingJob) == "table" then
            local task = {}
            for k, v in pairs(cpu.craftingJob) do
                task[k] = v
            end
            task.cpu = task.cpu or {
                name = cpu.name,
                storage = cpu.storage,
                index = index
            }
            table.insert(derived, task)
        end
    end
    return derived
end

local function getCPULabel(cpu, index, total)
    return "CPU " .. index .. "/" .. total .. " (" .. Text.formatBytesAsK(cpu.storage or 0) .. ")"
end

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
        return AEViewSupport.mount()
    end,

    init = function(self, config)
        AEViewSupport.init(self)
        self.showStorage = config.showStorage or false
        self.totalStorage = 0
    end,

    getData = function(self)
        -- Lazy re-init: retry if host not yet discovered at init time
        if not AEViewSupport.ensureInterface(self) then return nil end

        -- Get all CPUs
        local cpus = self.interface:getCraftingCPUs()
        if not cpus then return {} end

        -- Get crafting tasks (for busy CPUs)
        local tasksOk, tasksData = pcall(function()
            return self.interface:getCraftingTasks()
        end)
        local tasks = (tasksOk and type(tasksData) == "table") and tasksData or {}
        if #tasks == 0 then
            tasks = buildTasksFromCPUJobs(cpus)
        end
        local tasksByCpuIndex = buildTaskMap(cpus, tasks)

        self.totalStorage = 0
        local rows = {}
        for index, cpu in ipairs(cpus) do
            self.totalStorage = self.totalStorage + (cpu.storage or 0)
            rows[index] = {
                cpu = cpu,
                index = index,
                total = #cpus,
                task = tasksByCpuIndex[index]
            }
        end

        return rows
    end,

    header = function(self, data)
        return {
            text = "Crafting CPUs",
            color = colors.white,
            secondary = " (" .. #data .. " | " .. Text.formatBytesAsK(self.totalStorage) .. ")",
            secondaryColor = colors.gray
        }
    end,

    -- Keep cells compact so small monitors still show item/status on line 2.
    cellHeight = 2,

    formatItem = function(self, entry)
        local cpuData = entry.cpu
        local lines = {}
        local lineColors = {}

        table.insert(lines, getCPULabel(cpuData, entry.index, entry.total))
        table.insert(lineColors, colors.white)

        if cpuData.isBusy then
            table.insert(lines, getCraftingItemLabel(entry.task))
            table.insert(lineColors, colors.yellow)
        else
            local idleText = "IDLE"
            if self.showStorage and cpuData.coProcessors and cpuData.coProcessors > 0 then
                idleText = idleText .. " " .. cpuData.coProcessors .. "cp"
            end
            table.insert(lines, idleText)
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
