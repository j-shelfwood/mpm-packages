-- ItemChanges.lua
-- Displays accumulated inventory changes over a configurable time period
-- Shows items that increased or decreased

local AEInterface = mpm('peripherals/AEInterface')
local GridDisplay = mpm('utils/GridDisplay')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')

local module

module = {
    sleepTime = 1,

    configSchema = {
        {
            key = "periodSeconds",
            type = "number",
            label = "Reset Period (sec)",
            default = 1800,
            min = 60,
            max = 86400,
            presets = {60, 300, 600, 1800, 3600}
        }
    },

    new = function(monitor, config)
        config = config or {}
        local width, height = monitor.getSize()

        local self = {
            monitor = monitor,
            width = width,
            height = height,
            periodSeconds = config.periodSeconds or 1800,
            interface = nil,
            display = GridDisplay.new(monitor),
            prevItems = {},
            accumulatedChanges = {},
            lastReset = os.epoch("utc"),
            initialized = false
        }

        local ok, interface = pcall(AEInterface.new)
        if ok and interface then
            self.interface = interface
            -- Initialize previous items
            local itemsOk, items = pcall(function() return interface:items() end)
            if itemsOk and items then
                for _, item in ipairs(items) do
                    self.prevItems[item.registryName] = item.count
                end
            end
        end

        return self
    end,

    mount = function()
        return AEInterface.exists()
    end,

    formatChange = function(name, change)
        local color = change > 0 and colors.green or colors.red
        local sign = change > 0 and "+" or ""
        return {
            lines = { Text.prettifyName(name), sign .. Text.formatNumber(change, 0) },
            colors = { colors.white, color }
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

        -- Check for period reset
        local now = os.epoch("utc")
        if (now - self.lastReset) / 1000 >= self.periodSeconds then
            self.accumulatedChanges = {}
            self.lastReset = now
        end

        -- Get current items
        local ok, currItems = pcall(function() return self.interface:items() end)
        if not ok or not currItems then
            MonitorHelpers.writeCentered(self.monitor, 1, "Error fetching items", colors.red)
            return
        end

        -- Build current lookup
        local currLookup = {}
        for _, item in ipairs(currItems) do
            currLookup[item.registryName] = item.count
        end

        -- Calculate changes
        for id, count in pairs(currLookup) do
            local prevCount = self.prevItems[id] or 0
            local change = count - prevCount
            if change ~= 0 then
                self.accumulatedChanges[id] = (self.accumulatedChanges[id] or 0) + change
            end
        end

        -- Check for removed items
        for id, prevCount in pairs(self.prevItems) do
            if not currLookup[id] then
                local change = -prevCount
                self.accumulatedChanges[id] = (self.accumulatedChanges[id] or 0) + change
            end
        end

        -- Update previous state
        self.prevItems = currLookup

        -- Convert to display format
        local displayItems = {}
        for id, change in pairs(self.accumulatedChanges) do
            if change ~= 0 then
                table.insert(displayItems, { id = id, change = change })
            end
        end

        -- Handle empty
        if #displayItems == 0 then
            self.monitor.clear()
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Item Changes", colors.white)
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "No changes detected", colors.gray)

            -- Show time until reset
            local elapsed = math.floor((now - self.lastReset) / 1000)
            local remaining = self.periodSeconds - elapsed
            local resetStr = "Reset in " .. remaining .. "s"
            self.monitor.setTextColor(colors.gray)
            self.monitor.setCursorPos(1, self.height)
            self.monitor.write(resetStr)
            return
        end

        -- Sort by absolute change descending
        table.sort(displayItems, function(a, b)
            return math.abs(a.change) > math.abs(b.change)
        end)

        -- Draw header
        self.monitor.clear()
        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(1, 1)
        self.monitor.write("Item Changes")

        -- Time indicator
        local elapsed = math.floor((now - self.lastReset) / 1000)
        local remaining = self.periodSeconds - elapsed
        local timeStr = remaining .. "s"
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(math.max(1, self.width - #timeStr + 1), 1)
        self.monitor.write(timeStr)

        -- Display changes
        self.display:display(displayItems, function(item)
            return module.formatChange(item.id, item.change)
        end)

        self.monitor.setTextColor(colors.white)
    end
}

return module
