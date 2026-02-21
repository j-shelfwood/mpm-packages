-- ItemBrowser.lua
-- Full ME network inventory browser with search and interactive details
-- Touch an item to see details and craft if available
-- Uses ResourceBrowserFactory for shared implementation

local ResourceBrowserFactory = mpm('views/factories/ResourceBrowserFactory')

return ResourceBrowserFactory.create({
    name = "Item",
    dataMethod = "items",
    idField = "registryName",
    amountField = "count",
    unitDivisor = 1,
    unitLabel = "",
    titleColor = colors.lightGray,
    headerColor = colors.cyan,
    amountColor = colors.gray,
    highlightColor = colors.lime,
    craftAmounts = {1, 16, 64},
    craftMethod = "craftItem",
    lowThreshold = 64,
    emptyMessage = "No items in storage",
    footerText = "Touch for details"
})
