-- InventoryChangesDisplay.lua
-- Displays accumulated inventory changes over a configurable time period
-- Supports: me_bridge (Advanced Peripherals), merequester:requester

local AEInterface = mpm('peripherals/AEInterface')
local GridDisplay = mpm('utils/GridDisplay')
local Text = mpm('utils/Text')

local module

-- Default configuration
local DEFAULT_CONFIG = {
    accumulationPeriod = 1800, -- 30 minutes
    updateInterval = 1
}

module = {
    sleepTime = 1,

    new = function(monitor, config)
        config = config or {}

        -- Merge with defaults
        local mergedConfig = {
            accumulationPeriod = config.accumulationPeriod or DEFAULT_CONFIG.accumulationPeriod,
            updateInterval = config.updateInterval or DEFAULT_CONFIG.updateInterval
        }

        local interface = AEInterface.new() -- Auto-detects peripheral
        local self = {
            monitor = monitor,
            interface = interface,
            display = GridDisplay.new(monitor),
            prevItems = {},
            accumulatedChanges = {},
            config = mergedConfig
        }
        self.monitor.clear()

        -- Initialize previous items from current state (with error handling)
        local ok, items = pcall(AEInterface.items, interface)
        if ok and items then
            for _, item in ipairs(items) do
                self.prevItems[item.name] = item.count
            end
        end

        return self
    end,

    -- Reset accumulated changes (called periodically)
    clearState = function(self)
        self.accumulatedChanges = {}
    end,

    mount = function()
        return AEInterface.exists()
    end,

    configure = function()
        print("Enter accumulation period in seconds (default 1800 = 30 min):")
        local period = tonumber(read()) or 1800
        return {
            accumulationPeriod = period,
            updateInterval = 1
        }
    end,

    format_callback = function(key, value)
        local color = value > 0 and colors.green or colors.red
        local sign = value > 0 and "+" or ""
        return {
            lines = {Text.prettifyItemIdentifier(key), sign .. tostring(value)},
            colors = {colors.white, color}
        }
    end,

    render = function(self)
        -- Update changes with error handling
        local ok, err = pcall(module.updateAccumulatedChanges, self)
        if not ok then
            self.monitor.clear()
            self.monitor.setCursorPos(1, 1)
            self.monitor.write("Error updating:")
            self.monitor.setCursorPos(1, 2)
            self.monitor.write(tostring(err):sub(1, 30))
            return
        end

        -- Convert accumulated changes to display format
        local displayItems = {}
        for name, change in pairs(self.accumulatedChanges) do
            if change ~= 0 then
                table.insert(displayItems, {name = name, change = change})
            end
        end

        -- Handle empty state
        if #displayItems == 0 then
            self.monitor.clear()
            local width, height = self.monitor.getSize()
            self.monitor.setCursorPos(1, math.floor(height / 2) - 1)
            self.monitor.write("Inventory Changes")
            self.monitor.setCursorPos(1, math.floor(height / 2) + 1)
            self.monitor.write("No changes detected")
            return
        end

        -- Sort by absolute change value descending
        table.sort(displayItems, function(a, b)
            return math.abs(a.change) > math.abs(b.change)
        end)

        self.display:display(displayItems, function(item)
            return module.format_callback(item.name, item.change)
        end)
    end,

    updateAccumulatedChanges = function(self)
        local currItems = AEInterface.items(self.interface)

        -- Build lookup of current items
        local currLookup = {}
        for _, item in ipairs(currItems) do
            currLookup[item.name] = item.count
        end

        -- Compare with previous state
        for name, count in pairs(currLookup) do
            local prevCount = self.prevItems[name] or 0
            local change = count - prevCount
            if change ~= 0 then
                self.accumulatedChanges[name] = (self.accumulatedChanges[name] or 0) + change
            end
        end

        -- Check for items that were removed entirely
        for name, prevCount in pairs(self.prevItems) do
            if not currLookup[name] then
                local change = -prevCount
                self.accumulatedChanges[name] = (self.accumulatedChanges[name] or 0) + change
            end
        end

        -- Update previous state
        self.prevItems = currLookup
    end
}

return module
