-- FluidList.lua
-- Displays all fluids in the ME network as a grid
-- Shows fluid name and amount in buckets with color coding

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
        return AEInterface.exists()
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil
        self.warningBelow = config.warningBelow or 100
        self.sortBy = config.sortBy or "amount"
        self.totalBuckets = 0  -- Will be calculated in getData
    end,

    getData = function(self)
        -- Check interface is available
        if not self.interface then return nil end

        -- Get all fluids
        local fluids = self.interface:fluids()
        if not fluids then return {} end

        -- Sort fluids
        if self.sortBy == "amount" then
            -- Sort by amount descending (most first)
            table.sort(fluids, function(a, b)
                return (a.amount or 0) > (b.amount or 0)
            end)
        elseif self.sortBy == "name" then
            -- Sort alphabetically
            table.sort(fluids, function(a, b)
                local nameA = a.displayName or a.registryName or ""
                local nameB = b.displayName or b.registryName or ""
                return nameA < nameB
            end)
        end

        -- Calculate total volume
        self.totalBuckets = 0
        for _, fluid in ipairs(fluids) do
            self.totalBuckets = self.totalBuckets + (fluid.amount / 1000)
        end

        return fluids
    end,

    header = function(self, data)
        return {
            text = "Fluids",
            color = colors.cyan,
            secondary = " (" .. #data .. " | " .. Text.formatNumber(self.totalBuckets, 0) .. "B)",
            secondaryColor = colors.gray
        }
    end,

    formatItem = function(self, fluid)
        local buckets = fluid.amount / 1000

        -- Color code by amount
        local amountColor = colors.cyan
        if buckets < self.warningBelow then
            amountColor = colors.red
        elseif buckets < self.warningBelow * 2 then
            amountColor = colors.orange
        end

        -- Prefer displayName over registryName
        local name = fluid.displayName or fluid.registryName or "Unknown"
        if name == fluid.registryName then
            name = Text.prettifyName(name)
        end

        return {
            lines = {
                name,
                Text.formatNumber(buckets, 0) .. "B"
            },
            colors = { colors.white, amountColor }
        }
    end,

    emptyMessage = "No fluids in network",
    maxItems = 50
})
