-- ChemicalList.lua
-- Displays all Mekanism chemicals in the ME network as a grid
-- Requires: Applied Mekanistics addon for ME Bridge
-- Shows chemical name and amount with color coding
-- Uses ListFactory for shared implementation

local ListFactory = mpm('views/factories/ListFactory')
local AEInterface = mpm('peripherals/AEInterface')

return ListFactory.create({
    name = "Chemical",
    dataMethod = "chemicals",
    amountField = "amount",
    unitDivisor = 1000,
    unitLabel = "B",
    headerColor = colors.lightBlue,
    amountColor = colors.lightBlue,
    warningDefault = 100,
    warningPresets = {10, 50, 100, 500, 1000},
    maxItems = 50,
    emptyMessage = "No chemicals in network",
    requireChemicalSupport = true,
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
