-- FluidMonitor.lua
-- Displays AE2 fluid storage with change tracking
-- Supports: me_bridge (Advanced Peripherals), merequester:requester

local AEInterface = mpm('peripherals/AEInterface')
local GridDisplay = mpm('utils/GridDisplay')
local Text = mpm('utils/Text')

local module

module = {
    sleepTime = 1,

    new = function(monitor, config)
        local self = {
            monitor = monitor,
            display = GridDisplay.new(monitor),
            interface = nil,
            prev_fluids = {}
        }

        -- Try to create interface (may fail if no peripheral)
        local ok, interface = pcall(AEInterface.new)
        if ok and interface then
            self.interface = interface
            local fluidOk, fluids = pcall(AEInterface.fluids, interface)
            if fluidOk and fluids then
                self.prev_fluids = fluids
            end
        end

        return self
    end,

    mount = function()
        return AEInterface.exists()
    end,

    format_callback = function(fluid)
        local color = fluid.operation == "+" and colors.green or fluid.operation == "-" and colors.red or colors.white
        local _, _, name = string.find(fluid.name or "", ":(.+)")
        name = name and name:gsub("^%l", string.upper) or (fluid.name or "Unknown")
        local change = (fluid.change and fluid.change ~= 0) and (fluid.operation or "") .. Text.formatFluidAmount(fluid.change) or ""
        return {
            lines = {name, Text.formatFluidAmount(fluid.amount or 0), change},
            colors = {colors.white, colors.white, color}
        }
    end,

    render = function(self)
        -- Check if interface exists
        if not self.interface then
            self.monitor.clear()
            local width, height = self.monitor.getSize()
            self.monitor.setCursorPos(1, math.floor(height / 2) - 1)
            self.monitor.write("Fluid Monitor")
            self.monitor.setCursorPos(1, math.floor(height / 2) + 1)
            self.monitor.write("No AE2 peripheral found")
            return
        end

        -- Fetch fluids with error handling
        local ok, current_fluids = pcall(AEInterface.fluids, self.interface)
        if not ok or not current_fluids then
            self.monitor.clear()
            self.monitor.setCursorPos(1, 1)
            self.monitor.write("Error fetching fluids")
            return
        end

        -- Handle empty fluids
        if #current_fluids == 0 then
            self.monitor.clear()
            local width, height = self.monitor.getSize()
            self.monitor.setCursorPos(1, math.floor(height / 2) - 1)
            self.monitor.write("Fluid Monitor")
            self.monitor.setCursorPos(1, math.floor(height / 2) + 1)
            self.monitor.write("No fluids in network")
            self.prev_fluids = current_fluids
            return
        end

        local changesOk, changes = pcall(AEInterface.fluid_changes, self.interface, self.prev_fluids or {})
        if not changesOk then
            changes = {}
        end

        -- Mark all current fluids with no change as having a change of 0
        for _, fluid in ipairs(current_fluids) do
            local found = false
            for _, change in ipairs(changes) do
                if change.name == fluid.name then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(changes, {
                    name = fluid.name,
                    amount = fluid.amount,
                    change = 0,
                    operation = ""
                })
            end
        end

        -- Sort by fluid.amount in descending order
        table.sort(changes, function(a, b)
            return (a.amount or 0) > (b.amount or 0)
        end)

        -- Limit to top 30
        local displayChanges = {}
        for i = 1, math.min(30, #changes) do
            table.insert(displayChanges, changes[i])
        end

        self.display:display(displayChanges, function(item)
            return module.format_callback(item)
        end)

        self.prev_fluids = current_fluids
    end
}

return module
