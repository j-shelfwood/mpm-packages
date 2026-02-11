-- InventoryDisplay.lua
-- Displays AE2 network items with change indicators
-- Supports: me_bridge (Advanced Peripherals), merequester:requester

local AEInterface = mpm('peripherals/AEInterface')
local GridDisplay = mpm('utils/GridDisplay')
local Text = mpm('utils/Text')

local module

module = {
    sleepTime = 1,

    new = function(monitor, config)
        local self = {
            monitor = monitor,
            interface = nil,
            display = GridDisplay.new(monitor),
            prevItems = {}
        }

        -- Try to create interface (may fail if no peripheral)
        local ok, interface = pcall(AEInterface.new)
        if ok and interface then
            self.interface = interface
        end

        return self
    end,

    mount = function()
        return AEInterface.exists()
    end,

    format_callback = function(item)
        local color = item.change == "+" and colors.green or item.change == "-" and colors.red or colors.white
        return {
            lines = {Text.prettifyItemIdentifier(item.name or "Unknown"), tostring(item.count or 0), item.change or ""},
            colors = {colors.white, colors.white, color}
        }
    end,

    render = function(self)
        -- Check if interface exists
        if not self.interface then
            self.monitor.clear()
            local width, height = self.monitor.getSize()
            self.monitor.setCursorPos(1, math.floor(height / 2) - 1)
            self.monitor.write("Inventory Display")
            self.monitor.setCursorPos(1, math.floor(height / 2) + 1)
            self.monitor.write("No AE2 peripheral found")
            return
        end

        -- Fetch items with error handling
        local ok, items = pcall(AEInterface.items, self.interface)
        if not ok or not items then
            self.monitor.clear()
            self.monitor.setCursorPos(1, 1)
            self.monitor.write("Error fetching items")
            self.monitor.setCursorPos(1, 2)
            self.monitor.write(tostring(items or "unknown"):sub(1, 30))
            return
        end

        -- Handle empty items
        if #items == 0 then
            self.monitor.clear()
            local width, height = self.monitor.getSize()
            self.monitor.setCursorPos(1, math.floor(height / 2) - 1)
            self.monitor.write("Inventory Display")
            self.monitor.setCursorPos(1, math.floor(height / 2) + 1)
            self.monitor.write("No items in network")
            return
        end

        -- Sort by count descending
        table.sort(items, function(a, b)
            return (a.count or 0) > (b.count or 0)
        end)

        -- Track changes
        local currItems = {}
        for i, item in ipairs(items) do
            local itemName = item.name or "unknown"
            local itemCount = item.count or 0
            local itemChange = ""

            if self.prevItems[itemName] then
                local change = itemCount - (self.prevItems[itemName].count or 0)
                if change > 0 then
                    itemChange = "+"
                elseif change < 0 then
                    itemChange = "-"
                end
            end

            self.prevItems[itemName] = {
                count = itemCount
            }

            currItems[i] = {
                name = itemName,
                count = itemCount,
                change = itemChange
            }
        end

        self.display:display(currItems, function(item)
            return module.format_callback(item)
        end)
    end
}

return module
