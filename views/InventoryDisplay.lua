-- InventoryDisplay.lua
-- Displays AE2 network items with change indicators
-- Supports: me_bridge (Advanced Peripherals), merequester:requester

local AEInterface = mpm('peripherals/AEInterface')
local GridDisplay = mpm('utils/GridDisplay')
local Text = mpm('utils/Text')

local module

module = {
    sleepTime = 1,

    new = function(monitor)
        local interface = AEInterface.new() -- Auto-detects peripheral
        local self = {
            monitor = monitor,
            interface = interface,
            display = GridDisplay.new(monitor),
            prevItems = {}
        }
        return self
    end,

    mount = function()
        return AEInterface.exists()
    end,

    format_callback = function(item)
        local color = item.change == "+" and colors.green or item.change == "-" and colors.red or colors.white
        return {
            lines = {Text.prettifyItemIdentifier(item.name), tostring(item.count), item.change or ""},
            colors = {colors.white, colors.white, color}
        }
    end,

    render = function(self)
        local items = AEInterface.items(self.interface)

        -- If there are no items, print a message
        if #items == 0 then
            print("No items in inventory")
            return
        end

        -- Sort by count descending
        table.sort(items, function(a, b)
            return a.count > b.count
        end)

        -- Track changes
        local currItems = {}
        for i, item in ipairs(items) do
            local itemName = item.name
            local itemCount = item.count
            local itemChange = ""

            if self.prevItems[itemName] then
                local change = itemCount - self.prevItems[itemName].count
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
