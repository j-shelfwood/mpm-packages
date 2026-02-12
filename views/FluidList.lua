-- FluidList.lua
-- Displays all fluids in the ME network as a grid
-- Shows fluid name and amount in buckets with color coding

local AEInterface = mpm('peripherals/AEInterface')
local GridDisplay = mpm('utils/GridDisplay')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

local module

module = {
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

    new = function(monitor, config)
        config = config or {}
        local width, height = monitor.getSize()

        local self = {
            monitor = monitor,
            width = width,
            height = height,
            warningBelow = config.warningBelow or 100,
            sortBy = config.sortBy or "amount",
            interface = nil,
            display = GridDisplay.new(monitor),
            initialized = false
        }

        local ok, interface = pcall(AEInterface.new)
        if ok and interface then
            self.interface = interface
        end

        return self
    end,

    mount = function()
        return AEInterface.exists()
    end,

    formatFluid = function(fluid, warningBelow)
        local buckets = fluid.amount / 1000
        
        -- Color code by amount
        local amountColor = colors.cyan
        if buckets < warningBelow then
            amountColor = colors.red
        elseif buckets < warningBelow * 2 then
            amountColor = colors.orange
        end

        local lines = {
            Text.prettifyName(fluid.registryName or "Unknown"),
            Text.formatNumber(buckets, 0) .. "B"
        }
        local lineColors = { colors.white, amountColor }

        return {
            lines = lines,
            colors = lineColors
        }
    end,

    render = function(self)
        if not self.initialized then
            self.monitor.clear()
            self.initialized = true
        end

        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)

        if not self.interface then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No AE2 peripheral", colors.red)
            return
        end

        -- Get all fluids
        local ok, fluids = pcall(function() return self.interface:fluids() end)
        if not ok or not fluids then
            MonitorHelpers.writeCentered(self.monitor, 1, "Error fetching fluids", colors.red)
            return
        end

        -- Yield after peripheral call
        Yield.yield()

        -- Handle no fluids
        if #fluids == 0 then
            self.monitor.clear()
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Fluids", colors.cyan)
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "No fluids in network", colors.gray)
            return
        end

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
        local totalBuckets = 0
        for _, fluid in ipairs(fluids) do
            totalBuckets = totalBuckets + (fluid.amount / 1000)
        end

        -- Limit display
        local maxFluids = 50
        local displayFluids = {}
        for i = 1, math.min(#fluids, maxFluids) do
            displayFluids[i] = fluids[i]
        end

        -- Display fluids in grid (let GridDisplay handle clearing)
        local warningBelow = self.warningBelow
        self.display:display(displayFluids, function(fluid)
            return module.formatFluid(fluid, warningBelow)
        end)

        -- Draw header overlay after grid (so it doesn't get erased)
        self.monitor.setTextColor(colors.cyan)
        self.monitor.setCursorPos(1, 1)
        self.monitor.write("Fluids")
        self.monitor.setTextColor(colors.gray)
        local countStr = " (" .. #fluids .. " | " .. Text.formatNumber(totalBuckets, 0) .. "B)"
        self.monitor.write(Text.truncateMiddle(countStr, self.width - 6))

        self.monitor.setTextColor(colors.white)
    end
}

return module
