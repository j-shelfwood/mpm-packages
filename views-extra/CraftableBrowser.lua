-- CraftableBrowser.lua
-- Interactive browser for craftable items with one-tap crafting
-- Touch an item to see details and trigger crafting
-- Supports low stock and out-of-stock filtering modes
-- Uses ResourceBrowserFactory for shared implementation

local ResourceBrowserFactory = mpm('views/factories/ResourceBrowserFactory')

return ResourceBrowserFactory.create({
    name = "Craftable",
    dataMethod = "items",  -- Not used directly, craftableSource overrides
    idField = "registryName",
    amountField = "count",
    unitDivisor = 1,
    unitLabel = "",
    titleColor = colors.lightGray,
    headerColor = colors.cyan,
    amountColor = colors.white,
    highlightColor = colors.white,  -- All items are craftable, no special highlight
    craftAmounts = {1, 16, 64, 256},
    craftMethod = "craftItem",
    lowThreshold = 64,
    emptyMessage = "No craftable items",
    footerText = "Touch to craft",
    sortAscending = true,
    craftableSource = true,  -- Fetch from craftable list, merge with stock
    alwaysCraftable = true,
    skipDefaultConfig = true,

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

    filterData = function(self, resources)
        local filtered = {}
        local showMode = self.showMode or "all"
        local threshold = self.lowThreshold or 64

        for _, resource in ipairs(resources) do
            local count = resource.count or 0
            local include = false

            if showMode == "all" then
                include = true
            elseif showMode == "zeroStock" then
                include = (count == 0)
            elseif showMode == "lowStock" then
                include = (count < threshold)
            end

            if include then
                table.insert(filtered, resource)
            end
        end

        return filtered
    end,

    getHeader = function(self, data)
        local headerText = "CRAFTABLE"
        local headerColor = colors.cyan

        if self.showMode == "zeroStock" then
            headerText = "OUT OF STOCK"
            headerColor = colors.red
        elseif self.showMode == "lowStock" then
            headerText = "LOW STOCK"
            headerColor = colors.orange
        end

        return {
            text = headerText,
            color = headerColor,
            secondary = " (" .. #data .. "/" .. self.totalCount .. ")",
            secondaryColor = colors.gray
        }
    end
})
