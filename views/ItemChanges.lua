-- ItemChanges.lua
-- Tracks and displays inventory changes over a configurable time period
-- Uses ChangesFactory for shared implementation

local ChangesFactory = mpm('views/factories/ChangesFactory')

return ChangesFactory.create({
    name = "Item",
    dataMethod = "items",
    idField = "registryName",
    amountField = "count",
    unitDivisor = 1,
    unitLabel = "",
    titleColor = colors.white,
    barColor = colors.blue,
    accentColor = colors.cyan,
    defaultMinChange = 1
})
