-- Import monitor API
local generics = require("generics")

-- Function to track input of items
function trackInput(monitorSide, peripheralSide, scale)
    -- Get a reference to the monitor and the peripheral
    local monitor = peripheral.wrap(monitorSide)
    local interface = peripheral.wrap(peripheralSide)

    -- Set text scale
    monitor.setTextScale(scale or 1)

    -- Get the monitor dimensions and calculate the number of columns and rows
    local monitorWidth, monitorHeight = monitor.getSize()
    local numColumns = math.ceil(monitorWidth / 15)
    local numRows = math.ceil(monitorHeight / 3)

    -- Initialize the previous items table and the changes table
    local prevItems = {}
    local changes = {}

    -- Continuously fetch and display the items
    while true do
        -- Get items
        local items = interface.getAllStacks(false)

        for _, item in ipairs(items) do
            local itemName = generics.shortenName(item.display_name, math.floor(monitorWidth / numColumns))
            local itemCount = item.qty

            -- Save the current count for the next update
            local prevCount = prevItems[itemName] or 0
            prevItems[itemName] = itemCount

            -- Calculate the change from the previous count and update the changes table
            local change = itemCount - prevCount
            changes[itemName] = {
                change = change,
                symbol = change >= 0 and "+" or "-"
            }
        end

        -- Display changes in the grid
        generics.displayChangesInGrid(monitor, changes, numColumns, numRows)

        sleep(60)
    end
end

-- Automatically find the sides
local monitorSide = generics.findPeripheralSide("monitor")
local peripheralSide = generics.findPeripheralSide("merequester:requester")

if not monitorSide then
    print("Monitor not found.")
    return
end

if not peripheralSide then
    print("ME Interface not found.")
    return
end

-- Call the function to track the input of items
trackInput(monitorSide, peripheralSide, 0.5) -- last parameter is text scale, default to 1 if not provided
