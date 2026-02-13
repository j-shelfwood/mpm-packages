-- FluidChanges.lua
-- Tracks and displays fluid changes over a configurable time period
-- Uses ChangesFactory for shared implementation

local ChangesFactory = mpm('views/factories/ChangesFactory')

return ChangesFactory.create({
    name = "Fluid",
    dataMethod = "fluids",
    idField = "registryName",
    amountField = "amount",
    unitDivisor = 1000,
    unitLabel = "B",
    titleColor = colors.cyan,
    barColor = colors.cyan,
    accentColor = colors.cyan,
    defaultMinChange = 1000
})
