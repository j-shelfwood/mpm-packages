-- CraftingQueueDisplay.lua
-- Displays active AE2 crafting jobs and CPU status
-- Supports: me_bridge (Advanced Peripherals)

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
            interface = nil
        }

        -- Try to create interface
        local ok, interface = pcall(AEInterface.new)
        if ok and interface then
            self.interface = interface
        end

        return self
    end,

    mount = function()
        local exists, pType = AEInterface.exists()
        -- Only mount if we have me_bridge (crafting requires it)
        return exists and pType == "me_bridge"
    end,

    format_cpu = function(cpu)
        local status = cpu.isBusy and "BUSY" or "IDLE"
        local statusColor = cpu.isBusy and colors.orange or colors.green
        return {
            lines = {cpu.name or "CPU", status, tostring(cpu.storage or 0) .. "B"},
            colors = {colors.white, statusColor, colors.lightGray}
        }
    end,

    render = function(self)
        local width, height = self.monitor.getSize()

        -- Check if interface exists
        if not self.interface then
            self.monitor.clear()
            self.monitor.setCursorPos(1, math.floor(height / 2) - 1)
            self.monitor.write("Crafting Queue")
            self.monitor.setCursorPos(1, math.floor(height / 2) + 1)
            self.monitor.write("No ME Bridge found")
            return
        end

        -- Get crafting CPUs
        local ok, cpus = pcall(AEInterface.getCraftingCPUs, self.interface)
        if not ok or not cpus then
            self.monitor.clear()
            self.monitor.setCursorPos(1, 1)
            self.monitor.write("Error fetching CPUs")
            return
        end

        -- Handle no CPUs
        if #cpus == 0 then
            self.monitor.clear()
            self.monitor.setCursorPos(1, math.floor(height / 2) - 1)
            self.monitor.write("Crafting Queue")
            self.monitor.setCursorPos(1, math.floor(height / 2) + 1)
            self.monitor.write("No Crafting CPUs")
            return
        end

        -- Count busy/idle
        local busyCount = 0
        for _, cpu in ipairs(cpus) do
            if cpu.isBusy then
                busyCount = busyCount + 1
            end
        end

        -- Clear and draw header
        self.monitor.clear()
        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(1, 1)
        self.monitor.write("Crafting CPUs")

        -- Status summary
        self.monitor.setCursorPos(width - 10, 1)
        if busyCount > 0 then
            self.monitor.setTextColor(colors.orange)
            self.monitor.write(busyCount .. "/" .. #cpus .. " busy")
        else
            self.monitor.setTextColor(colors.green)
            self.monitor.write("All idle")
        end

        -- Display CPUs in grid (offset by 2 rows for header)
        local displayCpus = {}
        for _, cpu in ipairs(cpus) do
            table.insert(displayCpus, cpu)
        end

        -- Sort busy first
        table.sort(displayCpus, function(a, b)
            if a.isBusy ~= b.isBusy then
                return a.isBusy
            end
            return (a.name or "") < (b.name or "")
        end)

        if #displayCpus > 0 then
            self.display:display(displayCpus, module.format_cpu)
        end
    end
}

return module
