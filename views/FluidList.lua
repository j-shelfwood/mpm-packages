-- FluidList.lua
-- Displays all fluids in the ME network as a grid
-- Shows fluid name and amount in buckets with color coding
-- Uses ListFactory for shared implementation

local ListFactory = mpm('views/factories/ListFactory')

return ListFactory.create({
    name = "Fluid",
    dataMethod = "fluids",
    amountField = "amount",
    unitDivisor = 1000,
    unitLabel = "B",
    headerColor = colors.cyan,
    amountColor = colors.cyan,
    warningDefault = 100,
    warningPresets = {10, 50, 100, 500, 1000},
    maxItems = 50,
    emptyMessage = "No fluids in network"
})
