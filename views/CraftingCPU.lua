-- CraftingCPU.lua
-- Displays status of a single AE2 crafting CPU
-- Configurable: which CPU to monitor

local BaseView = mpm('views/BaseView')
local AEViewSupport = mpm('views/AEViewSupport')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

local function getCPUDisplayLabel(cpu, index, total)
    local capacity = Text.formatBytesAsK(cpu and cpu.storage or 0)
    local prefix = "CPU " .. tostring(index or "?")
    if total and total > 0 then
        prefix = prefix .. "/" .. total
    end
    return prefix .. " (" .. capacity .. ")"
end

local function resolveSelectedCPU(cpus, selector)
    if not cpus or #cpus == 0 or selector == nil then
        return nil, nil
    end

    if type(selector) == "string" then
        local idxFromPrefixed = selector:match("^index:(%d+)$")
        if idxFromPrefixed then
            local idx = tonumber(idxFromPrefixed)
            if idx and cpus[idx] then
                return cpus[idx], idx
            end
        end

        local idxFromRaw = tonumber(selector)
        if idxFromRaw and cpus[idxFromRaw] then
            return cpus[idxFromRaw], idxFromRaw
        end
    elseif type(selector) == "number" then
        local idx = math.floor(selector)
        if cpus[idx] then
            return cpus[idx], idx
        end
    end

    -- Backwards compatibility with legacy name-based config.
    for i, cpu in ipairs(cpus) do
        if cpu.name == selector then
            return cpu, i
        end
    end

    return nil, nil
end

local function buildTaskDetail(task)
    if not task then return nil end
    local parts = {}
    local quantity = task.quantity or (task.resource and task.resource.count)
    if quantity then
        table.insert(parts, "x" .. Text.formatNumber(quantity, 0))
    end
    if type(task.completion) == "number" then
        local percent = math.floor(task.completion * 100 + 0.5)
        table.insert(parts, percent .. "%")
    end
    if #parts == 0 then return nil end
    return table.concat(parts, " ")
end

-- Get available CPUs for config picker
local function getCPUOptions()
    if not AEViewSupport.mount() then return {} end
    local probe = {}
    local interface = AEViewSupport.init(probe)
    if not interface then return {} end

    local cpusOk, cpus = pcall(function() return interface:getCraftingCPUs() end)
    if not cpusOk or not cpus then return {} end

    local options = {}
    for index, cpu in ipairs(cpus) do
        table.insert(options, {
            value = "index:" .. index,
            label = getCPUDisplayLabel(cpu, index, #cpus)
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
        return AEViewSupport.mount()
    end,

    init = function(self, config)
        AEViewSupport.init(self)
        self.cpuSelector = config.cpu
    end,

    getData = function(self)
        -- Lazy re-init: retry if host not yet discovered at init time
        if not AEViewSupport.ensureInterface(self) then return nil end

        if not self.cpuSelector then
            return nil
        end

        -- Get all CPUs and find ours
        local cpus = self.interface:getCraftingCPUs()
        if not cpus then return nil end

        Yield.yield()

        local cpu, cpuIndex = resolveSelectedCPU(cpus, self.cpuSelector)

        if not cpu then
            return { notFound = true, selector = self.cpuSelector }
        end

        -- Get crafting task info if busy
        local currentTask = nil
        if cpu.isBusy then
            local tasksOk, tasks = pcall(function() return self.interface:getCraftingTasks() end)
            Yield.yield()
            if tasksOk and tasks then
                -- Prefer explicit name match when available and meaningful.
                for _, task in ipairs(tasks) do
                    local taskCpuName = type(task.cpu) == "table" and task.cpu.name or task.cpu
                    if cpu.name and cpu.name ~= "" and cpu.name ~= "Unnamed" and taskCpuName == cpu.name then
                        currentTask = task
                        break
                    end
                end

                -- Fallback: map task by busy CPU order when names are duplicated/unnamed.
                if not currentTask then
                    local busyRank = 0
                    for i, c in ipairs(cpus) do
                        if c.isBusy then
                            busyRank = busyRank + 1
                        end
                        if i == cpuIndex then
                            break
                        end
                    end

                    if busyRank > 0 then
                        local seenBusyTasks = 0
                        for _, task in ipairs(tasks) do
                            seenBusyTasks = seenBusyTasks + 1
                            if seenBusyTasks == busyRank then
                                currentTask = task
                                break
                            end
                        end
                    end
                end
            end
        end

        return {
            cpu = cpu,
            cpuIndex = cpuIndex,
            totalCPUs = #cpus,
            currentTask = currentTask
        }
    end,

    render = function(self, data)
        if data.notFound then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "CPU not found", colors.red)
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, tostring(data.selector or "?"), colors.gray)
            return
        end

        local cpu = data.cpu

        -- Row 1: CPU index + capacity
        local name = Text.truncateMiddle(getCPUDisplayLabel(cpu, data.cpuIndex, data.totalCPUs), self.width)
        MonitorHelpers.writeCentered(self.monitor, 1, name, colors.white)

        -- Center area: Status
        local centerY = math.floor(self.height / 2)

        if cpu.isBusy then
            -- Show BUSY status
            MonitorHelpers.writeCentered(self.monitor, centerY - 1, "CRAFTING", colors.orange)

            -- Show current task info
            if data.currentTask then
                local itemName = "Unknown"
                if data.currentTask.resource and data.currentTask.resource.displayName then
                    itemName = data.currentTask.resource.displayName
                elseif data.currentTask.resource and data.currentTask.resource.name then
                    itemName = Text.prettifyName(data.currentTask.resource.name)
                elseif data.currentTask.name or data.currentTask.item then
                    itemName = Text.prettifyName(data.currentTask.name or data.currentTask.item)
                end
                itemName = Text.prettifyName(itemName)
                itemName = Text.truncateMiddle(itemName, self.width - 2)
                MonitorHelpers.writeCentered(self.monitor, centerY + 1, itemName, colors.yellow)

                -- Progress bar for active job
                local completion = data.currentTask.completion
                if type(completion) == "number" and centerY + 2 < self.height then
                    local percent = completion * 100
                    local barColor = colors.orange
                    if percent >= 75 then
                        barColor = colors.lime
                    elseif percent >= 50 then
                        barColor = colors.yellow
                    end
                    MonitorHelpers.drawProgressBar(self.monitor, 1, centerY + 2, self.width, percent, barColor, colors.gray, true)
                end

                -- Detail text below progress bar
                local detail = buildTaskDetail(data.currentTask)
                if detail and centerY + 3 < self.height then
                    MonitorHelpers.writeCentered(self.monitor, centerY + 3, detail, colors.gray)
                end
            end
        else
            -- Show IDLE status
            MonitorHelpers.writeCentered(self.monitor, centerY, "IDLE", colors.lime)
        end

        -- Bottom: Storage info
        self.monitor.setTextColor(colors.gray)
        local storageStr = Text.formatBytesAsK(cpu.storage or 0) .. " storage"
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
