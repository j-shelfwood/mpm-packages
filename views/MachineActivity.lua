-- MachineActivity.lua
-- Unified machine activity display for MI, Mekanism, and other mods
-- Shows categorized grid of machines with activity status

local BaseView = mpm('views/BaseView')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')
local Activity = mpm('peripherals/MachineActivity')

-- Display modes
local MODE_ALL = "all"           -- All machines grouped by category
local MODE_CATEGORY = "category" -- Single category
local MODE_TYPE = "type"         -- Single machine type

return BaseView.custom({
    sleepTime = 0.5,  -- Fast updates for activity monitoring

    configSchema = {
        {
            key = "mod_filter",
            type = "select",
            label = "Mod Filter",
            options = Activity.getModFilters,
            default = "all"
        },
        {
            key = "display_mode",
            type = "select",
            label = "Display Mode",
            options = function()
                return {
                    { value = MODE_ALL, label = "All (Categorized Grid)" },
                    { value = MODE_TYPE, label = "Single Machine Type" }
                }
            end,
            default = MODE_ALL
        },
        {
            key = "machine_type",
            type = "select",
            label = "Machine Type",
            options = function(config)
                return Activity.getMachineTypes(config.mod_filter or "all")
            end,
            dependsOn = "mod_filter",
            showWhen = function(config)
                return config.display_mode == MODE_TYPE
            end
        }
    },

    mount = function()
        -- Check if any machines with activity support exist
        local discovered = Activity.discoverAll()
        return next(discovered) ~= nil
    end,

    init = function(self, config)
        self.modFilter = config.mod_filter or "all"
        self.displayMode = config.display_mode or MODE_ALL
        self.machineType = config.machine_type
    end,

    getData = function(self)
        if self.displayMode == MODE_TYPE and self.machineType then
            -- Single type mode
            local discovered = Activity.discoverAll()
            local typeData = discovered[self.machineType]

            if not typeData then
                return { mode = MODE_TYPE, machines = {}, typeName = self.machineType }
            end

            local machines = {}
            for idx, machine in ipairs(typeData.machines) do
                local isActive, activityData = Activity.getActivity(machine.peripheral)
                table.insert(machines, {
                    name = machine.name:match("_(%d+)$") or tostring(idx),
                    isActive = isActive,
                    data = activityData
                })
                Yield.check(idx, 5)
            end

            return {
                mode = MODE_TYPE,
                machines = machines,
                typeName = Activity.getShortName(self.machineType),
                classification = typeData.classification
            }
        else
            -- All mode - grouped by category
            local groups = Activity.groupByCategory(self.modFilter)

            -- Process each group to get current activity
            local processedGroups = {}
            local totalIdx = 0

            for catName, catData in pairs(groups) do
                local processedTypes = {}
                local catActive = 0
                local catTotal = 0

                for pType, typeInfo in pairs(catData.types) do
                    local typeActive = 0
                    local machines = {}

                    for _, machine in ipairs(typeInfo.machines) do
                        totalIdx = totalIdx + 1
                        local isActive, activityData = Activity.getActivity(machine.peripheral)
                        if isActive then
                            typeActive = typeActive + 1
                            catActive = catActive + 1
                        end
                        catTotal = catTotal + 1

                        table.insert(machines, {
                            name = machine.name:match("_(%d+)$") or "?",
                            isActive = isActive,
                            data = activityData
                        })
                        Yield.check(totalIdx, 10)
                    end

                    processedTypes[pType] = {
                        shortName = Activity.getShortName(pType),
                        machines = machines,
                        active = typeActive,
                        total = #machines
                    }
                end

                processedGroups[catName] = {
                    label = catData.label,
                    color = catData.color,
                    types = processedTypes,
                    active = catActive,
                    total = catTotal
                }
            end

            return {
                mode = MODE_ALL,
                groups = processedGroups
            }
        end
    end,

    render = function(self, data)
        if data.mode == MODE_TYPE then
            self:renderSingleType(data)
        else
            self:renderCategorized(data)
        end
    end,

    renderSingleType = function(self, data)
        local machines = data.machines

        if #machines == 0 then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No machines found", colors.orange)
            return
        end

        -- Title
        local title = data.typeName or "Machines"
        MonitorHelpers.writeCentered(self.monitor, 1, title, data.classification and data.classification.color or colors.white)

        -- Calculate grid
        local cellSize = 3
        local cols = math.floor((self.width - 1) / (cellSize + 1))
        if cols < 1 then cols = 1 end

        local startY = 3
        local activeCount = 0

        for idx, machine in ipairs(machines) do
            local col = (idx - 1) % cols
            local row = math.floor((idx - 1) / cols)
            local x = col * (cellSize + 1) + 2
            local y = startY + row * (cellSize + 1)

            if y + cellSize > self.height - 1 then break end

            -- Draw cell
            local bgColor = machine.isActive and colors.green or colors.gray
            self.monitor.setBackgroundColor(bgColor)

            for i = 0, cellSize - 1 do
                self.monitor.setCursorPos(x, y + i)
                self.monitor.write(string.rep(" ", cellSize))
            end

            -- Draw label
            self.monitor.setTextColor(colors.black)
            local label = tostring(machine.name):sub(1, cellSize)
            local labelX = x + math.floor((cellSize - #label) / 2)
            self.monitor.setCursorPos(labelX, y + math.floor(cellSize / 2))
            self.monitor.write(label)

            if machine.isActive then activeCount = activeCount + 1 end
        end

        -- Status bar
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(1, self.height)
        self.monitor.write(string.format("%d/%d active", activeCount, #machines))
    end,

    renderCategorized = function(self, data)
        local groups = data.groups

        if not groups or not next(groups) then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No machines found", colors.orange)
            return
        end

        -- Title
        local filterLabel = self.modFilter == "all" and "All Machines" or
                           (self.modFilter == "mekanism" and "Mekanism" or "Modern Industrialization")
        MonitorHelpers.writeCentered(self.monitor, 1, filterLabel, colors.white)

        -- Sort categories for consistent display
        local sortedCats = {}
        for catName, catData in pairs(groups) do
            table.insert(sortedCats, { name = catName, data = catData })
        end
        table.sort(sortedCats, function(a, b) return a.data.label < b.data.label end)

        -- Calculate layout
        local y = 3
        local cellSize = 2
        local cellGap = 1
        local sectionGap = 1

        local totalActive = 0
        local totalMachines = 0

        for _, cat in ipairs(sortedCats) do
            local catData = cat.data

            if y >= self.height - 2 then break end

            -- Category header
            self.monitor.setBackgroundColor(colors.black)
            self.monitor.setTextColor(catData.color or colors.white)
            self.monitor.setCursorPos(1, y)
            local headerText = string.format("%s (%d/%d)", catData.label, catData.active, catData.total)
            self.monitor.write(headerText:sub(1, self.width))
            y = y + 1

            totalActive = totalActive + catData.active
            totalMachines = totalMachines + catData.total

            -- Sort types within category
            local sortedTypes = {}
            for pType, typeInfo in pairs(catData.types) do
                table.insert(sortedTypes, { type = pType, info = typeInfo })
            end
            table.sort(sortedTypes, function(a, b) return a.info.shortName < b.info.shortName end)

            -- Draw machines for each type
            local x = 1
            for _, typeEntry in ipairs(sortedTypes) do
                local typeInfo = typeEntry.info

                for _, machine in ipairs(typeInfo.machines) do
                    -- Check if we need to wrap
                    if x + cellSize > self.width then
                        x = 1
                        y = y + cellSize + cellGap
                    end

                    if y + cellSize > self.height - 1 then break end

                    -- Draw cell
                    local bgColor = machine.isActive and colors.green or colors.gray
                    self.monitor.setBackgroundColor(bgColor)

                    for i = 0, cellSize - 1 do
                        self.monitor.setCursorPos(x, y + i)
                        self.monitor.write(string.rep(" ", cellSize))
                    end

                    x = x + cellSize + cellGap
                end

                if y + cellSize > self.height - 1 then break end
            end

            -- Move to next section
            if x > 1 then y = y + cellSize + cellGap end
            y = y + sectionGap
        end

        -- Bottom status
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(1, self.height)
        self.monitor.write(string.format("Total: %d/%d active", totalActive, totalMachines))
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Machine Activity", colors.white)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "No compatible machines found", colors.gray)
    end
})
