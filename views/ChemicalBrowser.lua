-- ChemicalBrowser.lua
-- Interactive ME network chemical browser with touch details
-- Requires: Applied Mekanistics addon for ME Bridge
-- Touch a chemical to see details and craft if available
-- Uses ResourceBrowserFactory for shared implementation

local ResourceBrowserFactory = mpm('views/factories/ResourceBrowserFactory')
local AEInterface = mpm('peripherals/AEInterface')

return ResourceBrowserFactory.create({
    name = "Chemical",
    dataMethod = "chemicals",
    idField = "registryName",
    amountField = "amount",
    unitDivisor = 1000,
    unitLabel = "B",
    titleColor = colors.lightBlue,
    headerColor = colors.lightBlue,
    amountColor = colors.lightBlue,
    highlightColor = colors.lime,
    craftAmounts = {1000, 10000, 100000},
    craftMethod = "craftChemical",
    getCraftableMethod = "getCraftableChemicals",
    lowThreshold = 100,
    amountLabel = "Amount: ",
    emptyMessage = "No chemicals in storage",
    craftUnavailableMessage = "Chemical crafting unavailable",
    mountCheck = function()
        if not AEInterface or type(AEInterface.exists) ~= "function" then
            return false
        end
        local ok, exists, bridge = pcall(AEInterface.exists)
        if not ok or not exists or not bridge then
            return false
        end
        return type(bridge.getChemicals) == "function"
    end
})
