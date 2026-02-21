-- CraftingQueue.lua
-- Displays all active crafting jobs across all CPUs in the AE2 network
-- Touch a job to see details and cancel if desired

local BaseView = mpm('views/BaseView')
local AEViewSupport = mpm('views/AEViewSupport')
local Text = mpm('utils/Text')
local Core = mpm('ui/Core')
local Yield = mpm('utils/Yield')
local ModalOverlay = mpm('ui/ModalOverlay')

local function getTaskResource(task)
    if type(task) ~= "table" then return nil end
    if type(task.resource) == "table" then
        return task.resource
    end
    return nil
end

local function getTaskDisplayName(task)
    local resource = getTaskResource(task)
    if resource and resource.displayName then
        return resource.displayName
    end
    if resource and resource.name then
        return Text.prettifyName(resource.name)
    end
    if task and (task.name or task.item) then
        return Text.prettifyName(task.name or task.item)
    end
    return "Unknown"
end

local function getTaskQuantity(task)
    if not task then return 0 end
    if task.quantity ~= nil then
        return task.quantity
    end
    local resource = getTaskResource(task)
    if resource and resource.count ~= nil then
        return resource.count
    end
    return 0
end

local function getTaskCpuName(task)
    if not task or not task.cpu then return nil end
    if type(task.cpu) == "table" then
        return task.cpu.name
    end
    return tostring(task.cpu)
end

local function makeCPULabel(index, total, storageBytes)
    local capacity = Text.formatBytesAsK(storageBytes or 0)
    local prefix = "CPU " .. tostring(index or "?")
    if total and total > 0 then
        prefix = prefix .. "/" .. total
    end
    return prefix .. " (" .. capacity .. ")"
end

local function buildCPULookup(cpus)
    local byUniqueName = {}
    local counts = {}
    local totalStorage = 0

    for _, cpu in ipairs(cpus or {}) do
        totalStorage = totalStorage + (cpu.storage or 0)
        local name = cpu.name
        if name and name ~= "" then
            counts[name] = (counts[name] or 0) + 1
        end
    end

    for index, cpu in ipairs(cpus or {}) do
        local name = cpu.name
        if name and counts[name] == 1 then
            byUniqueName[name] = { index = index, cpu = cpu }
        end
    end

    return {
        byUniqueName = byUniqueName,
        totalCPUs = #(cpus or {}),
        totalStorage = totalStorage
    }
end

local function resolveTaskCPULabel(task, lookup)
    local taskCpuName = getTaskCpuName(task)
    if taskCpuName and lookup and lookup.byUniqueName and lookup.byUniqueName[taskCpuName] then
        local entry = lookup.byUniqueName[taskCpuName]
        return makeCPULabel(entry.index, lookup.totalCPUs, entry.cpu.storage)
    end

    if type(task.cpu) == "table" then
        local cpu = task.cpu
        if cpu.index then
            return makeCPULabel(cpu.index, lookup and lookup.totalCPUs, cpu.storage)
        end
        if cpu.storage then
            return "CPU (" .. Text.formatBytesAsK(cpu.storage) .. ")"
        end
    end

    return "CPU ?"
end

local function assignCPULabelsToTasks(tasks, cpus, lookup)
    local busyIndexes = {}
    for index, cpu in ipairs(cpus or {}) do
        if cpu.isBusy then
            table.insert(busyIndexes, index)
        end
    end

    local fallbackCursor = 1
    for _, task in ipairs(tasks or {}) do
        local label = resolveTaskCPULabel(task, lookup)
        if label == "CPU ?" and #busyIndexes > 0 then
            local idx = busyIndexes[((fallbackCursor - 1) % #busyIndexes) + 1]
            label = makeCPULabel(idx, #cpus, cpus[idx].storage)
            fallbackCursor = fallbackCursor + 1
        end
        task._cpuLabel = label
    end
end

local function buildTasksFromCPUJobs(cpus)
    local derived = {}
    local total = #(cpus or {})

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
            task._cpuLabel = makeCPULabel(index, total, cpu.storage)
            table.insert(derived, task)
        end
    end

    return derived
end

local function filterTasks(tasks, showCompleted)
    if showCompleted then
        return tasks
    end

    local filtered = {}
    for _, task in ipairs(tasks or {}) do
        local keep = true
        if type(task.completion) == "number" and task.completion >= 0.999 then
            keep = false
        end
        if keep then
            table.insert(filtered, task)
        end
    end
    return filtered
end

-- Task detail overlay with cancel button (blocking)
local function showTaskDetail(self, task)
    local itemName = getTaskDisplayName(task)

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
            local quantity = getTaskQuantity(task)

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
                monitor.setTextColor(colors.lightGray)
                monitor.setCursorPos(frame.x1 + 1, contentY)
                monitor.write("CPU: " .. Core.truncate(task._cpuLabel or "CPU ?", frame.width - 6))
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
                    local resource = getTaskResource(task)
                    if resource and resource.name then
                        filter.name = resource.name
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

local listenEvents, onEvent = AEViewSupport.buildListener({ "craftingCPUs", "craftingTasks" })

return BaseView.interactive({
    sleepTime = 1,
    listenEvents = listenEvents,
    onEvent = onEvent,

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
        self.totalStorage = 0
        self.dataUnavailable = false
    end,

    getData = function(self)
        -- Lazy re-init: retry if host not yet discovered at init time
        if not AEViewSupport.ensureInterface(self) then return nil end

        -- Bridge task list is sometimes empty unless jobs were started from this bridge.
        -- We'll fallback to busy CPUs' craftingJob data below.
        local tasksOk, tasks = pcall(function()
            return self.interface:getCraftingTasks()
        end)
        local taskState = AEViewSupport.readStatus(self, "craftingTasks").state
        tasks = (tasksOk and type(tasks) == "table") and tasks or {}
        self.dataUnavailable = (taskState == "unavailable" or taskState == "error")

        Yield.yield()

        -- Get CPU status for summary
        local cpusOk, cpus = pcall(function() return self.interface:getCraftingCPUs() end)
        local cpuState = AEViewSupport.readStatus(self, "craftingCPUs").state
        Yield.yield()
        self.dataUnavailable = self.dataUnavailable or (cpuState == "unavailable" or cpuState == "error")

        self.busyCount = 0
        self.totalCPUs = 0
        self.totalStorage = 0
        if cpusOk and cpus then
            self.totalCPUs = #cpus
            local lookup = buildCPULookup(cpus)
            self.totalStorage = lookup.totalStorage or 0
            for _, cpu in ipairs(cpus) do
                if cpu.isBusy then
                    self.busyCount = self.busyCount + 1
                end
            end

            assignCPULabelsToTasks(tasks, cpus, lookup)

            -- Fallback for AP/AE2 behavior where getCraftingTasks() can be empty:
            -- derive active jobs from each busy CPU's embedded craftingJob.
            if #tasks == 0 then
                tasks = buildTasksFromCPUJobs(cpus)
            end
        end

        return filterTasks(tasks, self.showCompleted)
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
        local itemName = getTaskDisplayName(task)

        -- Build detail string
        local detailParts = {}
        local quantity = getTaskQuantity(task)
        if quantity and quantity > 0 then
            table.insert(detailParts, "x" .. Text.formatNumber(quantity, 0))
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
        local footerText = self.busyCount .. "/" .. self.totalCPUs .. " busy | " .. Text.formatBytesAsK(self.totalStorage) .. " cap"
        if self.dataUnavailable then
            footerText = "Data stale/unavailable"
        end
        return {
            text = footerText,
            color = colors.gray
        }
    end,

    emptyMessage = "No active crafting jobs"
})
