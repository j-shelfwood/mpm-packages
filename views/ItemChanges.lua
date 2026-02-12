-- ItemChanges.lua
-- Displays accumulated inventory changes over a configurable time period
-- Shows items that increased or decreased
-- Optimized for large AE2 systems with periodic yields

local AEInterface = mpm('peripherals/AEInterface')
local GridDisplay = mpm('utils/GridDisplay')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')

-- Yield every N items to prevent blocking the event loop
local YIELD_INTERVAL = 100

local module

module = {
    -- Increased from 1 to 5 seconds to reduce load on large systems
    sleepTime = 5,

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
            -- Initialize previous items (with yields for large systems)
            local itemsOk, items = pcall(function() return interface:items() end)
            if itemsOk and items then
                local count = 0
                for _, item in ipairs(items) do
                    self.prevItems[item.registryName] = item.count
                    count = count + 1
                    if count % YIELD_INTERVAL == 0 then
                        os.sleep(0)  -- Yield to allow event processing
                    end
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

        -- Get current items (this is the main blocking call)
        local ok, currItems = pcall(function() return self.interface:items() end)
        if not ok or not currItems then
            MonitorHelpers.writeCentered(self.monitor, 1, "Error fetching items", colors.red)
            return
        end

        -- Yield after peripheral call to allow queued events to process
        os.sleep(0)

        -- Build current lookup (with periodic yields)
        local currLookup = {}
        local count = 0
        for _, item in ipairs(currItems) do
            currLookup[item.registryName] = item.count
            count = count + 1
            if count % YIELD_INTERVAL == 0 then
                os.sleep(0)
            end
        end

        -- Calculate changes (with periodic yields)
        count = 0
        for id, itemCount in pairs(currLookup) do
            local prevCount = self.prevItems[id] or 0
            local change = itemCount - prevCount
            if change ~= 0 then
                self.accumulatedChanges[id] = (self.accumulatedChanges[id] or 0) + change
            end
            count = count + 1
            if count % YIELD_INTERVAL == 0 then
                os.sleep(0)
            end
        end

        -- Check for removed items (with periodic yields)
        count = 0
        for id, prevCount in pairs(self.prevItems) do
            if not currLookup[id] then
                local change = -prevCount
                self.accumulatedChanges[id] = (self.accumulatedChanges[id] or 0) + change
            end
            count = count + 1
            if count % YIELD_INTERVAL == 0 then
                os.sleep(0)
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
