-- test_script.lua
-- Include required APIs
local AEInterface = mpm('peripherals/AEInterface')
local GridDisplay = mpm('utils/GridDisplay')

-- Detect monitor
local monitor = peripheral.find("monitor")
local gridDisplay = GridDisplay.new(monitor)

-- Function to sort items by count (descending)
local function sort_items(items)
    table.sort(items, function(a, b)
        return a.count > b.count
    end)
end

-- Formatting callback for GridDisplay
local function format_callback(item)
    local itemName = item.name:sub(1, 15) -- trim item name to fit in the cell
    local itemCount = tostring(item.count)
    return {
        line_1 = itemName,
        color_1 = colors.white,
        line_2 = itemCount,
        color_2 = colors.white,
        line_3 = "",
        color_3 = colors.white
    }
end

-- Fetch items and sort them
local items = AEInterface.items()
sort_items(items)

-- Display items in a grid, increasing the number of items every 10 seconds
while true do
    for i = 2, 6 do
        local num_items = 2 ^ i
        local display_items = {}
        for j = 1, num_items do
            table.insert(display_items, items[j])
        end
        gridDisplay:display(display_items, format_callback)
        os.sleep(4)
    end
end
