-- FluidMonitor.lua
-- Displays AE2 fluid storage with change tracking
-- Supports: me_bridge (Advanced Peripherals), merequester:requester

local AEInterface = mpm('peripherals/AEInterface')
local GridDisplay = mpm('utils/GridDisplay')
local Text = mpm('utils/Text')

local module

module = {
    sleepTime = 1,

    new = function(monitor)
        local interface = AEInterface.new() -- Auto-detects peripheral
        local self = {
            monitor = monitor,
            display = GridDisplay.new(monitor),
            interface = interface,
            prev_fluids = AEInterface.fluids(interface)
        }
        return self
    end,

    mount = function()
        return AEInterface.exists()
    end,

    format_callback = function(fluid)
        local color = fluid.operation == "+" and colors.green or fluid.operation == "-" and colors.red or colors.white
        local _, _, name = string.find(fluid.name, ":(.+)")
        name = name and name:gsub("^%l", string.upper) or fluid.name
        local change = fluid.change ~= 0 and fluid.operation .. Text.formatFluidAmount(fluid.change) or ""
        return {
            lines = {name, Text.formatFluidAmount(fluid.amount), change},
            colors = {colors.white, colors.white, color}
        }
    end,

    render = function(self)
        local current_fluids = AEInterface.fluids(self.interface)
        local changes = AEInterface.fluid_changes(self.interface, self.prev_fluids or {})

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
            return a.amount > b.amount
        end)

        -- Limit to top 30
        changes = {table.unpack(changes, 1, 30)}

        self.display:display(changes, function(item)
            return module.format_callback(item)
        end)

        print("Detected " .. #changes .. " fluids")
        self.prev_fluids = current_fluids
    end
}

return module
