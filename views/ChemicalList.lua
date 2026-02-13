-- ChemicalList.lua
-- Displays all Mekanism chemicals in the ME network as a grid
-- Requires: Applied Mekanistics addon for ME Bridge
-- Shows chemical name and amount with color coding
-- Consistent with FluidList pattern

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')

return BaseView.grid({
    sleepTime = 2,

    configSchema = {
        {
            key = "warningBelow",
            type = "number",
            label = "Warning Below (B)",
            default = 100,
            min = 1,
            max = 100000,
            presets = {10, 50, 100, 500, 1000}
        },
        {
            key = "sortBy",
            type = "select",
            label = "Sort By",
            options = {
                { value = "amount", label = "Amount" },
                { value = "name", label = "Name" }
            },
            default = "amount"
        }
    },

    mount = function()
        local exists, bridge = AEInterface.exists()
        if not exists or not bridge then
            return false
        end

        -- Check if Applied Mekanistics addon is loaded (chemicals support)
        local hasChemicals = type(bridge.getChemicals) == "function"
        return hasChemicals
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil
        self.warningBelow = config.warningBelow or 100
        self.sortBy = config.sortBy or "amount"
        self.totalBuckets = 0
    end,

    getData = function(self)
        -- Check interface is available
        if not self.interface then return nil end

        -- Check for chemical support
        if not self.interface:hasChemicalSupport() then
            return {}
        end

        -- Get all chemicals
        local chemicals = self.interface:chemicals()
        if not chemicals then return {} end

        -- Sort chemicals
        if self.sortBy == "amount" then
            -- Sort by amount descending (most first)
            table.sort(chemicals, function(a, b)
                return (a.amount or 0) > (b.amount or 0)
            end)
        elseif self.sortBy == "name" then
            -- Sort alphabetically
            table.sort(chemicals, function(a, b)
                local nameA = a.displayName or a.registryName or ""
                local nameB = b.displayName or b.registryName or ""
                return nameA < nameB
            end)
        end

        -- Calculate total volume
        self.totalBuckets = 0
        for _, chemical in ipairs(chemicals) do
            self.totalBuckets = self.totalBuckets + ((chemical.amount or 0) / 1000)
        end

        return chemicals
    end,

    header = function(self, data)
        return {
            text = "Chemicals",
            color = colors.lightBlue,
            secondary = " (" .. #data .. " | " .. Text.formatNumber(self.totalBuckets, 0) .. "B)",
            secondaryColor = colors.gray
        }
    end,

    formatItem = function(self, chemical)
        local buckets = (chemical.amount or 0) / 1000

        -- Color code by amount
        local amountColor = colors.lightBlue
        if buckets < self.warningBelow then
            amountColor = colors.red
        elseif buckets < self.warningBelow * 2 then
            amountColor = colors.orange
        end

        return {
            lines = {
                Text.prettifyName(chemical.registryName or "Unknown"),
                Text.formatNumber(buckets, 0) .. "B"
            },
            colors = { colors.white, amountColor }
        }
    end,

    emptyMessage = "No chemicals in network",
    maxItems = 50
})
