-- CraftableItems.lua
-- Displays items with crafting patterns available
-- Shows current stock levels and highlights low/zero stock items

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local Yield = mpm('utils/Yield')

return BaseView.grid({
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

    mount = function()
        return AEInterface.exists()
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil
        self.showMode = config.showMode or "all"
        self.lowThreshold = config.lowThreshold or 64
        self.totalCraftable = 0
    end,

    getData = function(self)
        -- Get craftable items from ME Bridge
        local craftableItems = self.interface.bridge.getCraftableItems()
        if not craftableItems then return {} end

        Yield.yield()

        self.totalCraftable = #craftableItems

        -- Get current stock levels
        local allItems = self.interface:items()
        if not allItems then return {} end

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

        return displayItems
    end,

    header = function(self, data)
        local headerText = "CRAFTABLE ITEMS"
        local headerColor = colors.cyan
        if self.showMode == "zeroStock" then
            headerText = "OUT OF STOCK"
        elseif self.showMode == "lowStock" then
            headerText = "LOW STOCK (< " .. self.lowThreshold .. ")"
        end

        return {
            text = headerText,
            color = headerColor,
            secondary = " (" .. #data .. "/" .. self.totalCraftable .. ")",
            secondaryColor = colors.gray
        }
    end,

    formatItem = function(self, item)
        local count = item.count or 0
        local countColor = colors.red

        if count == 0 then
            countColor = colors.red
        elseif count < 64 then
            countColor = colors.orange
        else
            countColor = colors.white
        end

        return {
            lines = {
                item.displayName or Text.prettifyName(item.registryName or "Unknown"),
                Text.formatNumber(count)
            },
            colors = { colors.white, countColor },
            aligns = { "left", "right" }
        }
    end,

    emptyMessage = "No craftable items",
    maxItems = 50
})
