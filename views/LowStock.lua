-- LowStock.lua
-- Displays items below a configurable stock threshold
-- Highlights craftable vs non-craftable items

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

    new = function(monitor, config)
        config = config or {}
        local width, height = monitor.getSize()

        local self = {
            monitor = monitor,
            width = width,
            height = height,
            threshold = config.threshold or 100,
            showCraftable = config.showCraftable ~= false,
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

    formatItem = function(item, showCraftable)
        local countColor = colors.red
        if item.count > 50 then
            countColor = colors.orange
        elseif item.count > 10 then
            countColor = colors.yellow
        end

        local lines = { Text.prettifyName(item.registryName or "Unknown"), tostring(item.count) }
        local lineColors = { colors.white, countColor }

        if showCraftable then
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

        -- Get all items
        local ok, items = pcall(function() return self.interface:items() end)
        if not ok or not items then
            MonitorHelpers.writeCentered(self.monitor, 1, "Error fetching items", colors.red)
            return
        end

        -- Yield after peripheral call
        Yield.yield()

        -- Filter to low stock (with yields for large systems)
        local threshold = self.threshold
        local lowStock = Yield.filter(items, function(item)
            return (item.count or 0) < threshold
        end)

        -- Sort by count ascending (lowest first)
        table.sort(lowStock, function(a, b)
            return (a.count or 0) < (b.count or 0)
        end)

        -- Handle no low stock
        if #lowStock == 0 then
            self.monitor.clear()
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Low Stock Alert", colors.green)
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "All items above " .. self.threshold, colors.gray)
            return
        end

        -- Limit display
        local maxItems = 50
        local displayItems = {}
        for i = 1, math.min(#lowStock, maxItems) do
            displayItems[i] = lowStock[i]
        end

        -- Display items in grid (let GridDisplay handle clearing)
        local showCraftable = self.showCraftable
        self.display:display(displayItems, function(item)
            return module.formatItem(item, showCraftable)
        end)

        -- Draw header overlay after grid (so it doesn't get erased)
        self.monitor.setTextColor(colors.red)
        self.monitor.setCursorPos(1, 1)
        self.monitor.write("LOW STOCK")
        self.monitor.setTextColor(colors.gray)
        local countStr = " (" .. #lowStock .. " < " .. self.threshold .. ")"
        self.monitor.write(Text.truncateMiddle(countStr, self.width - 10))

        self.monitor.setTextColor(colors.white)
    end
}

return module
