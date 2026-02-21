-- ChemicalChanges.lua
-- Tracks and displays Mekanism chemical changes over a configurable time period
-- Requires: Applied Mekanistics addon for ME Bridge
-- Uses ChangesFactory for shared implementation

local ChangesFactory = mpm('views/factories/ChangesFactory')
local AEInterface = mpm('peripherals/AEInterface')
local _ = AEInterface

return ChangesFactory.create({
    name = "Chemical",
    dataMethod = "chemicals",
    idField = "name",
    amountField = "count",
    unitDivisor = 1000,
    unitLabel = "B",
    titleColor = colors.lightBlue,
    barColor = colors.lightBlue,
    accentColor = colors.lightBlue,
    defaultMinChange = 1000,
    mountCheck = function(caps)
        return caps and caps.hasChemical == true
    end
})
