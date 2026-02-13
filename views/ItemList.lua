-- ItemList.lua
-- Displays all items in the ME network as a grid
-- Shows item name and count with color coding
-- Uses ListFactory for shared implementation

local ListFactory = mpm('views/factories/ListFactory')

return ListFactory.create({
    name = "Item",
    dataMethod = "items",
    amountField = "count",
    unitDivisor = 1,
    unitLabel = "",
    headerColor = colors.white,
    amountColor = colors.white,
    warningDefault = 64,
    warningPresets = {16, 64, 256, 1000, 10000},
    maxItems = 100,
    emptyMessage = "No items in network",
    showCraftableIndicator = true,
    showCraftableFilter = true
})
