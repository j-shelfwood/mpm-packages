-- EnergyOverview.lua
-- Cross-mod energy storage overview display
-- Shows all batteries/capacitors/cells grouped by mod

local BaseView = mpm('views/BaseView')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')
local EnergyInterface = mpm('peripherals/EnergyInterface')

return BaseView.custom({
    sleepTime = 1,
    listenEvents = {},

    configSchema = {
        {
            key = "mod_filter",
            type = "select",
            label = "Mod Filter",
            options = function()
                return EnergyInterface.getModFilterOptions()
            end,
            default = "all"
        },
        {
            key = "name_filter",
            type = "text",
            label = "Name Filter",
            default = "",
            description = "Filter by peripheral name (* = wildcard)"
        },
        {
            key = "display_mode",
            type = "select",
            label = "Display Mode",
            options = function()
                return {
                    { value = "grid", label = "Grid (Individual)" },
                    { value = "summary", label = "Summary (By Mod)" },
                    { value = "total", label = "Total Only" }
                }
            end,
            default = "grid"
        }
    },

    mount = function()
        return EnergyInterface.exists()
    end,

    init = function(self, config)
        self.modFilter = config.mod_filter or "all"
        self.nameFilter = config.name_filter or ""
        self.displayMode = config.display_mode or "grid"
    end,

    getData = function(self)
        local groups = EnergyInterface.discoverByMod()
        local totals = { stored = 0, capacity = 0, count = 0 }

        -- Filter by mod if specified
        if self.modFilter ~= "all" then
            local filtered = {}
            if groups[self.modFilter] then
                filtered[self.modFilter] = groups[self.modFilter]
            end
            groups = filtered
        end

        -- Apply name filter and calculate totals
        for mod, data in pairs(groups) do
            if self.nameFilter ~= "" then
                data.storages = EnergyInterface.filterByName(data.storages, self.nameFilter)
            end

            -- Update group totals
            data.stored = 0
            data.capacity = 0
            for _, storage in ipairs(data.storages) do
                local stored = storage.status.storedFE or storage.status.stored or 0
                local capacity = storage.status.capacityFE or storage.status.capacity or 0
                data.stored = data.stored + stored
                data.capacity = data.capacity + capacity
                totals.stored = totals.stored + stored
                totals.capacity = totals.capacity + capacity
                totals.count = totals.count + 1
            end
            data.percent = data.capacity > 0 and (data.stored / data.capacity) or 0
        end

        totals.percent = totals.capacity > 0 and (totals.stored / totals.capacity) or 0

        return {
            groups = groups,
            totals = totals
        }
    end,

    render = function(self, data)
        if data.totals.count == 0 then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No energy storage found", colors.orange)
            return
        end

        if self.displayMode == "total" then
            self:renderTotal(data)
        elseif self.displayMode == "summary" then
            self:renderSummary(data)
        else
            self:renderGrid(data)
        end
    end,

    renderTotal = function(self, data)
        local totals = data.totals
        local midY = math.floor(self.height / 2)

        -- Title
        MonitorHelpers.writeCentered(self.monitor, 1, "Energy Storage", colors.yellow)

        -- Big percentage
        local pctStr = string.format("%.1f%%", totals.percent * 100)
        self.monitor.setTextColor(colors.white)
        MonitorHelpers.writeCentered(self.monitor, midY - 1, pctStr, colors.white)

        -- Progress bar
        local barWidth = self.width - 4
        local barX = 3
        MonitorHelpers.drawProgressBar(self.monitor, barX, midY + 1, barWidth, totals.percent * 100, colors.green, colors.gray, false)

        -- Values
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.lightGray)
        local storedStr = EnergyInterface.formatEnergy(totals.stored)
        local capStr = EnergyInterface.formatEnergy(totals.capacity)
        MonitorHelpers.writeCentered(self.monitor, midY + 3, storedStr .. " / " .. capStr, colors.lightGray)

        -- Count
        self.monitor.setTextColor(colors.gray)
        MonitorHelpers.writeCentered(self.monitor, self.height, totals.count .. " storages", colors.gray)
    end,

    renderSummary = function(self, data)
        -- Title with total
        local title = string.format("Energy: %.1f%%", data.totals.percent * 100)
        MonitorHelpers.writeCentered(self.monitor, 1, title, colors.yellow)

        -- Sort groups by label
        local sortedGroups = {}
        for mod, groupData in pairs(data.groups) do
            if #groupData.storages > 0 then
                table.insert(sortedGroups, { mod = mod, data = groupData })
            end
        end
        table.sort(sortedGroups, function(a, b) return a.data.label < b.data.label end)

        local y = 3
        local barWidth = self.width - 12

        for _, group in ipairs(sortedGroups) do
            if y >= self.height - 1 then break end

            local gd = group.data

            -- Mod label
            self.monitor.setBackgroundColor(colors.black)
            self.monitor.setTextColor(gd.color)
            self.monitor.setCursorPos(1, y)
            self.monitor.write(gd.label:sub(1, 8))

            -- Count
            self.monitor.setTextColor(colors.gray)
            self.monitor.setCursorPos(10, y)
            self.monitor.write("x" .. #gd.storages)

            y = y + 1

            -- Progress bar
            MonitorHelpers.drawProgressBar(self.monitor, 1, y, barWidth, gd.percent * 100, colors.green, colors.gray, false)

            -- Percentage
            self.monitor.setBackgroundColor(colors.black)
            self.monitor.setTextColor(colors.white)
            self.monitor.setCursorPos(barWidth + 2, y)
            self.monitor.write(string.format("%3.0f%%", gd.percent * 100))

            y = y + 2
        end

        -- Bottom total
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(1, self.height)
        self.monitor.write(EnergyInterface.formatEnergy(data.totals.stored) .. " / " .. EnergyInterface.formatEnergy(data.totals.capacity))
    end,

    renderGrid = function(self, data)
        -- Title
        local title = string.format("Energy: %.1f%%", data.totals.percent * 100)
        MonitorHelpers.writeCentered(self.monitor, 1, title, colors.yellow)

        -- Flatten all storages with mod info
        local allStorages = {}
        for mod, groupData in pairs(data.groups) do
            for _, storage in ipairs(groupData.storages) do
                storage.modColor = groupData.color
                storage.modLabel = groupData.label
                table.insert(allStorages, storage)
            end
        end

        if #allStorages == 0 then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No storages match filter", colors.orange)
            return
        end

        -- Calculate grid
        local cellWidth = 6
        local cellHeight = 3
        local cols = math.floor((self.width - 1) / (cellWidth + 1))
        if cols < 1 then cols = 1 end

        local startY = 3

        for idx, storage in ipairs(allStorages) do
            local col = (idx - 1) % cols
            local row = math.floor((idx - 1) / cols)
            local x = col * (cellWidth + 1) + 1
            local y = startY + row * (cellHeight + 1)

            if y + cellHeight > self.height - 1 then break end

            local pct = storage.status.percent

            -- Background color based on fill level
            local bgColor = colors.gray
            if pct > 0.9 then
                bgColor = colors.green
            elseif pct > 0.5 then
                bgColor = colors.lime
            elseif pct > 0.25 then
                bgColor = colors.yellow
            elseif pct > 0.1 then
                bgColor = colors.orange
            elseif pct > 0 then
                bgColor = colors.red
            end

            -- Draw cell
            self.monitor.setBackgroundColor(bgColor)
            for i = 0, cellHeight - 1 do
                self.monitor.setCursorPos(x, y + i)
                self.monitor.write(string.rep(" ", cellWidth))
            end

            -- Short name
            self.monitor.setTextColor(colors.black)
            local label = storage.shortName:sub(1, cellWidth)
            self.monitor.setCursorPos(x, y)
            self.monitor.write(label)

            -- Percentage
            self.monitor.setCursorPos(x, y + 1)
            self.monitor.write(string.format("%3.0f%%", pct * 100))

            -- Mod indicator (colored dot)
            self.monitor.setCursorPos(x + cellWidth - 1, y + cellHeight - 1)
            self.monitor.setBackgroundColor(storage.modColor)
            self.monitor.write(" ")
        end

        -- Bottom status
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(1, self.height)
        self.monitor.write(string.format("%d storages | %s", data.totals.count, EnergyInterface.formatEnergy(data.totals.stored)))
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Energy Overview", colors.yellow)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "No energy storage detected", colors.gray)
    end
})
