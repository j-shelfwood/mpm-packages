-- LowStock.lua
-- Displays items below a configurable stock threshold
-- Highlights craftable vs non-craftable items

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local Yield = mpm('utils/Yield')

return BaseView.grid({
    sleepTime = 5,

    configSchema = {
        {
            key = "threshold",
            type = "number",
            label = "Threshold",
            default = 100,
            min = 1,
            max = 100000,
            presets = {10, 50, 100, 500, 1000, 5000}
        },
        {
            key = "showCraftable",
            type = "select",
            label = "Show Craftable",
            options = {
                { value = true, label = "Yes" },
                { value = false, label = "No" }
            },
            default = true
        }
    },

    mount = function()
        return AEInterface.exists()
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil
        self.threshold = config.threshold or 100
        self.showCraftable = config.showCraftable ~= false
    end,

    getData = function(self)
        -- Get all items
        local items = self.interface:items()
        if not items then return {} end

        -- Filter to low stock (with yields for large systems)
        local threshold = self.threshold
        local lowStock = Yield.filter(items, function(item)
            return (item.count or 0) < threshold
        end)

        -- Sort by count ascending (lowest first)
        table.sort(lowStock, function(a, b)
            return (a.count or 0) < (b.count or 0)
        end)

        return lowStock
    end,

    header = function(self, data)
        return {
            text = "LOW STOCK",
            color = colors.red,
            secondary = " (" .. #data .. " < " .. self.threshold .. ")",
            secondaryColor = colors.gray
        }
    end,

    formatItem = function(self, item)
        local countColor = colors.red
        if item.count > 50 then
            countColor = colors.orange
        elseif item.count > 10 then
            countColor = colors.yellow
        end

        local lines = { Text.prettifyName(item.registryName or "Unknown"), tostring(item.count) }
        local lineColors = { colors.white, countColor }

        if self.showCraftable then
            if item.isCraftable then
                table.insert(lines, "[CRAFT]")
                table.insert(lineColors, colors.lime)
            else
                table.insert(lines, "[!]")
                table.insert(lineColors, colors.red)
            end
        end

        return {
            lines = lines,
            colors = lineColors
        }
    end,

    renderEmpty = function(self)
        local MonitorHelpers = mpm('utils/MonitorHelpers')
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Low Stock Alert", colors.green)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "All items above " .. self.threshold, colors.gray)
    end,

    emptyMessage = "All items above threshold",
    maxItems = 50
})
