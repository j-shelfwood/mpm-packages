-- LowStockAlert.lua
-- Displays items below a configurable stock threshold
-- Highlights craftable vs non-craftable items
-- Supports: me_bridge (Advanced Peripherals), merequester:requester

local AEInterface = mpm('peripherals/AEInterface')
local GridDisplay = mpm('utils/GridDisplay')
local Text = mpm('utils/Text')

local module

-- Default thresholds
local DEFAULT_CONFIG = {
    threshold = 100,        -- Alert when below this count
    showCraftable = true,   -- Show craftable status
    maxItems = 50           -- Max items to display
}

module = {
    sleepTime = 5,  -- Check every 5 seconds

    new = function(monitor, config)
        config = config or {}

        local mergedConfig = {
            threshold = config.threshold or DEFAULT_CONFIG.threshold,
            showCraftable = config.showCraftable ~= false,
            maxItems = config.maxItems or DEFAULT_CONFIG.maxItems
        }

        local self = {
            monitor = monitor,
            display = GridDisplay.new(monitor),
            interface = nil,
            config = mergedConfig
        }

        -- Try to create interface
        local ok, interface = pcall(AEInterface.new)
        if ok and interface then
            self.interface = interface
        end

        return self
    end,

    mount = function()
        return AEInterface.exists()
    end,

    configure = function()
        print("Enter low stock threshold (default 100):")
        local threshold = tonumber(read()) or 100
        return {
            threshold = threshold,
            showCraftable = true,
            maxItems = 50
        }
    end,

    format_item = function(item)
        local countColor = colors.red
        if item.count > 50 then
            countColor = colors.orange
        elseif item.count > 10 then
            countColor = colors.yellow
        end

        local craftStatus = ""
        local craftColor = colors.gray
        if item.isCraftable then
            craftStatus = "[CRAFT]"
            craftColor = colors.lime
        else
            craftStatus = "[!]"
            craftColor = colors.red
        end

        return {
            lines = {Text.prettifyItemIdentifier(item.name or "Unknown"), tostring(item.count), craftStatus},
            colors = {colors.white, countColor, craftColor}
        }
    end,

    render = function(self)
        local width, height = self.monitor.getSize()

        -- Check if interface exists
        if not self.interface then
            self.monitor.clear()
            self.monitor.setCursorPos(1, math.floor(height / 2) - 1)
            self.monitor.write("Low Stock Alert")
            self.monitor.setCursorPos(1, math.floor(height / 2) + 1)
            self.monitor.write("No AE2 peripheral found")
            return
        end

        -- Get all items
        local ok, items = pcall(AEInterface.items, self.interface)
        if not ok or not items then
            self.monitor.clear()
            self.monitor.setCursorPos(1, 1)
            self.monitor.write("Error fetching items")
            return
        end

        -- Filter to low stock items
        local lowStock = {}
        for _, item in ipairs(items) do
            if (item.count or 0) < self.config.threshold then
                table.insert(lowStock, item)
            end
        end

        -- Sort by count ascending (lowest first)
        table.sort(lowStock, function(a, b)
            return (a.count or 0) < (b.count or 0)
        end)

        -- Limit to maxItems
        local displayItems = {}
        for i = 1, math.min(#lowStock, self.config.maxItems) do
            displayItems[i] = lowStock[i]
        end

        -- Handle no low stock items
        if #displayItems == 0 then
            self.monitor.clear()
            self.monitor.setTextColor(colors.green)
            self.monitor.setCursorPos(1, math.floor(height / 2) - 1)
            self.monitor.write("Low Stock Alert")
            self.monitor.setCursorPos(1, math.floor(height / 2) + 1)
            self.monitor.write("All items above " .. self.config.threshold)
            self.monitor.setTextColor(colors.white)
            return
        end

        -- Draw header
        self.monitor.clear()
        self.monitor.setTextColor(colors.red)
        self.monitor.setCursorPos(1, 1)
        self.monitor.write("LOW STOCK (" .. #lowStock .. " items < " .. self.config.threshold .. ")")
        self.monitor.setTextColor(colors.white)

        -- Display items
        self.display:display(displayItems, module.format_item)
    end
}

return module
