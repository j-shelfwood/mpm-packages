-- FluidBrowser.lua
-- Interactive ME network fluid browser with touch details
-- Touch a fluid to see details and craft if available
-- Uses ResourceBrowserFactory for shared implementation

local ResourceBrowserFactory = mpm('views/factories/ResourceBrowserFactory')

return ResourceBrowserFactory.create({
    name = "Fluid",
    dataMethod = "fluids",
    idField = "registryName",
    amountField = "amount",
    unitDivisor = 1000,
    unitLabel = "B",
    titleColor = colors.lightBlue,
    headerColor = colors.cyan,
    amountColor = colors.cyan,
    highlightColor = colors.lime,
    craftAmounts = {1000, 10000, 100000},
    craftMethod = "craftFluid",
    getCraftableMethod = "getCraftableFluids",
    lowThreshold = 100,
    amountLabel = "Amount: ",
    emptyMessage = "No fluids in storage"
})
