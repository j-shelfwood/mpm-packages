-- ItemList.lua
-- Displays all items in the ME network as a grid
-- Shows item name and count with color coding
-- Analogous to FluidList but for items

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')

return BaseView.grid({
    sleepTime = 2,

    configSchema = {
        {
            key = "warningBelow",
            type = "number",
            label = "Warning Below",
            default = 64,
            min = 1,
            max = 100000,
            presets = {16, 64, 256, 1000, 10000}
        },
        {
            key = "sortBy",
            type = "select",
            label = "Sort By",
            options = {
                { value = "count", label = "Count" },
                { value = "name", label = "Name" }
            },
            default = "count"
        },
        {
            key = "showCraftable",
            type = "select",
            label = "Show Craftable",
            options = {
                { value = "all", label = "All Items" },
                { value = "craftable", label = "Craftable Only" },
                { value = "stored", label = "Stored Only" }
            },
            default = "all"
        }
    },

    mount = function()
        return AEInterface.exists()
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil
        self.warningBelow = config.warningBelow or 64
        self.sortBy = config.sortBy or "count"
        self.showCraftable = config.showCraftable or "all"
        self.totalItems = 0
    end,

    getData = function(self)
        if not self.interface then return nil end

        -- Get all items
        local items = self.interface:items()
        if not items then return {} end

        -- Filter based on showCraftable
        local filtered = {}
        for _, item in ipairs(items) do
            local include = true
            if self.showCraftable == "craftable" then
                include = item.isCraftable == true
            elseif self.showCraftable == "stored" then
                include = (item.count or 0) > 0
            end

            if include then
                table.insert(filtered, item)
            end
        end

        -- Sort items
        if self.sortBy == "count" then
            table.sort(filtered, function(a, b)
                return (a.count or 0) > (b.count or 0)
            end)
        elseif self.sortBy == "name" then
            table.sort(filtered, function(a, b)
                local nameA = a.displayName or a.registryName or ""
                local nameB = b.displayName or b.registryName or ""
                return nameA < nameB
            end)
        end

        -- Calculate total
        self.totalItems = 0
        for _, item in ipairs(filtered) do
            self.totalItems = self.totalItems + (item.count or 0)
        end

        return filtered
    end,

    header = function(self, data)
        return {
            text = "Items",
            color = colors.white,
            secondary = " (" .. #data .. " | " .. Text.formatNumber(self.totalItems, 0) .. ")",
            secondaryColor = colors.gray
        }
    end,

    formatItem = function(self, item)
        local count = item.count or 0

        -- Color code by amount
        local countColor = colors.white
        if count < self.warningBelow then
            countColor = colors.red
        elseif count < self.warningBelow * 2 then
            countColor = colors.orange
        elseif count >= self.warningBelow * 10 then
            countColor = colors.lime
        end

        -- Prefer displayName over registryName
        local name = item.displayName or item.registryName or "Unknown"
        if name == item.registryName then
            name = Text.prettifyName(name)
        end

        -- Craftable indicator
        local countStr = Text.formatNumber(count, 0)
        if item.isCraftable and count == 0 then
            countStr = "[C]"
            countColor = colors.cyan
        elseif item.isCraftable then
            countStr = countStr .. "*"
        end

        return {
            lines = {
                name,
                countStr
            },
            colors = { colors.white, countColor }
        }
    end,

    emptyMessage = "No items in network",
    maxItems = 100
})
