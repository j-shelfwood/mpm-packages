-- CraftableItems.lua
-- Displays items with crafting patterns available
-- Shows current stock levels and highlights low/zero stock items

local AEInterface = mpm('peripherals/AEInterface')
local GridDisplay = mpm('utils/GridDisplay')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

local module

module = {
    sleepTime = 5,

    configSchema = {
        {
            key = "showMode",
            type = "select",
            label = "Show",
            options = {
                { value = "all", label = "All Craftable" },
                { value = "lowStock", label = "Low Stock Only" },
                { value = "zeroStock", label = "Out of Stock" }
            },
            default = "all"
        },
        {
            key = "lowThreshold",
            type = "number",
            label = "Low Stock Threshold",
            default = 64,
            min = 1,
            max = 1000,
            presets = {16, 32, 64, 128, 256}
        }
    },

    new = function(monitor, config)
        config = config or {}
        local width, height = monitor.getSize()

        local self = {
            monitor = monitor,
            width = width,
            height = height,
            showMode = config.showMode or "all",
            lowThreshold = config.lowThreshold or 64,
            interface = nil,
            display = GridDisplay.new(monitor),
            initialized = false
        }

        local ok, interface = pcall(AEInterface.new)
        if ok and interface then
            self.interface = interface
        end

        return self
    end,

    mount = function()
        return AEInterface.exists()
    end,

    formatItem = function(item)
        local count = item.count or 0
        local countColor = colors.red
        
        if count == 0 then
            countColor = colors.red
        elseif count < 64 then
            countColor = colors.orange
        else
            countColor = colors.white
        end

        local lines = {
            Text.prettifyName(item.registryName or "Unknown"),
            Text.formatNumber(count)
        }
        local lineColors = { colors.white, countColor }

        return {
            lines = lines,
            colors = lineColors
        }
    end,

    render = function(self)
        if not self.initialized then
            self.monitor.clear()
            self.initialized = true
        end

        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)

        if not self.interface then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No AE2 peripheral", colors.red)
            return
        end

        -- Get craftable items from ME Bridge
        local ok, craftableItems = pcall(function() 
            return self.interface.bridge.getCraftableItems() 
        end)
        
        if not ok or not craftableItems then
            MonitorHelpers.writeCentered(self.monitor, 1, "Error fetching craftable items", colors.red)
            return
        end

        Yield.yield()

        -- Build lookup table for craftable item names
        local craftableLookup = {}
        for _, item in ipairs(craftableItems) do
            if item.name then
                craftableLookup[item.name] = true
            end
        end

        -- Get current stock levels
        local ok2, allItems = pcall(function() return self.interface:items() end)
        if not ok2 or not allItems then
            MonitorHelpers.writeCentered(self.monitor, 1, "Error fetching stock levels", colors.red)
            return
        end

        Yield.yield()

        -- Build lookup for stock counts
        local stockLookup = {}
        for _, item in ipairs(allItems) do
            if item.registryName then
                stockLookup[item.registryName] = item.count or 0
            end
        end

        -- Combine data: craftable items with current stock
        local displayItems = {}
        for _, craftable in ipairs(craftableItems) do
            if craftable.name then
                local count = stockLookup[craftable.name] or 0
                
                -- Apply filter based on showMode
                local include = false
                if self.showMode == "all" then
                    include = true
                elseif self.showMode == "zeroStock" then
                    include = (count == 0)
                elseif self.showMode == "lowStock" then
                    include = (count < self.lowThreshold)
                end

                if include then
                    table.insert(displayItems, {
                        registryName = craftable.name,
                        displayName = craftable.displayName or craftable.name,
                        count = count
                    })
                end
            end
        end

        Yield.yield()

        -- Sort by count (lowest first)
        table.sort(displayItems, function(a, b)
            if a.count == b.count then
                return (a.displayName or "") < (b.displayName or "")
            end
            return a.count < b.count
        end)

        -- Handle no results
        if #displayItems == 0 then
            self.monitor.clear()
            local modeLabel = "No Results"
            if self.showMode == "all" then
                modeLabel = "No Craftable Items"
            elseif self.showMode == "zeroStock" then
                modeLabel = "No Out of Stock Items"
            elseif self.showMode == "lowStock" then
                modeLabel = "No Low Stock Items"
            end
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, modeLabel, colors.green)
            if self.showMode == "lowStock" then
                MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Threshold: " .. self.lowThreshold, colors.gray)
            end
            return
        end

        -- Limit display for performance
        local maxItems = 50
        local limitedItems = {}
        for i = 1, math.min(#displayItems, maxItems) do
            limitedItems[i] = displayItems[i]
        end

        -- Display items in grid (let GridDisplay handle clearing)
        self.display:display(limitedItems, function(item)
            return module.formatItem(item)
        end)

        -- Draw header overlay after grid (so it doesn't get erased)
        self.monitor.setTextColor(colors.cyan)
        self.monitor.setCursorPos(1, 1)

        local headerText = "CRAFTABLE ITEMS"
        if self.showMode == "zeroStock" then
            headerText = "OUT OF STOCK"
        elseif self.showMode == "lowStock" then
            headerText = "LOW STOCK (< " .. self.lowThreshold .. ")"
        end

        self.monitor.write(headerText)
        self.monitor.setTextColor(colors.gray)
        local countStr = " (" .. #displayItems .. ")"
        self.monitor.write(countStr)

        self.monitor.setTextColor(colors.white)
    end
}

return module
