-- ItemChanges.lua
-- Tracks and displays inventory changes over a configurable time period
-- Compares current inventory against a baseline taken at period start
-- Fixed: Proper state machine to avoid double-snapshot issues

local AEInterface = mpm('peripherals/AEInterface')
local GridDisplay = mpm('utils/GridDisplay')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

local module

module = {
    sleepTime = 3,

    configSchema = {
        {
            key = "periodSeconds",
            type = "number",
            label = "Reset Period (sec)",
            default = 60,
            min = 10,
            max = 86400,
            presets = {30, 60, 300, 600, 1800}
        },
        {
            key = "showMode",
            type = "select",
            label = "Show Changes",
            options = {
                { value = "both", label = "Gains & Losses" },
                { value = "gains", label = "Gains Only" },
                { value = "losses", label = "Losses Only" }
            },
            default = "both"
        },
        {
            key = "minChange",
            type = "number",
            label = "Min Change",
            default = 1,
            min = 1,
            max = 1000,
            presets = {1, 10, 50, 100}
        }
    },

    new = function(monitor, config)
        config = config or {}
        local width, height = monitor.getSize()

        local self = {
            monitor = monitor,
            width = width,
            height = height,
            periodSeconds = config.periodSeconds or 60,
            showMode = config.showMode or "both",
            minChange = config.minChange or 1,
            interface = nil,
            display = GridDisplay.new(monitor),
            -- State machine
            state = "init",  -- "init", "baseline_set", "tracking"
            -- Baseline snapshot (frozen at period start)
            baseline = {},
            baselineCount = 0,
            -- When the current tracking period started
            periodStart = 0,
            -- Render counter (for skipping comparison on baseline frame)
            renderCount = 0
        }

        -- Try to connect to AE2
        local ok, interface = pcall(AEInterface.new)
        if ok and interface then
            self.interface = interface
        end

        return self
    end,

    mount = function()
        return AEInterface.exists()
    end,

    -- Take a snapshot of current item counts
    -- Returns: table {[registryName] = count}, itemCount, success
    takeSnapshot = function(self)
        if not self.interface then
            return {}, 0, false
        end

        local ok, items = pcall(function() return self.interface:items() end)
        if not ok or not items or #items == 0 then
            return {}, 0, false
        end

        Yield.yield()

        local snapshot = {}
        local count = 0

        for _, item in ipairs(items) do
            if item.registryName then
                local itemCount = item.count or 0
                if itemCount > 0 then
                    snapshot[item.registryName] = (snapshot[item.registryName] or 0) + itemCount
                    count = count + 1
                end
            end
            -- Yield periodically
            if count % 100 == 0 then
                Yield.yield()
            end
        end

        return snapshot, count, true
    end,

    -- Deep copy a table (to prevent reference issues)
    copySnapshot = function(snapshot)
        local copy = {}
        for k, v in pairs(snapshot) do
            copy[k] = v
        end
        return copy
    end,

    -- Calculate changes between baseline and current
    calculateChanges = function(self, current)
        local changes = {}
        local showMode = self.showMode
        local minChange = self.minChange
        local baseline = self.baseline

        if not baseline or not current then
            return changes
        end

        -- Track which baseline items we've seen
        local seen = {}

        -- Check current items against baseline
        for id, currCount in pairs(current) do
            seen[id] = true
            local baseCount = baseline[id] or 0
            local change = currCount - baseCount

            if change ~= 0 and math.abs(change) >= minChange then
                local include = (showMode == "both") or
                    (showMode == "gains" and change > 0) or
                    (showMode == "losses" and change < 0)

                if include then
                    table.insert(changes, {
                        id = id,
                        change = change,
                        current = currCount,
                        baseline = baseCount
                    })
                end
            end
        end

        -- Check for items completely removed (in baseline but not in current)
        for id, baseCount in pairs(baseline) do
            if not seen[id] and baseCount > 0 then
                local change = -baseCount
                if math.abs(change) >= minChange then
                    local include = (showMode == "both") or (showMode == "losses")
                    if include then
                        table.insert(changes, {
                            id = id,
                            change = change,
                            current = 0,
                            baseline = baseCount
                        })
                    end
                end
            end
        end

        return changes
    end,

    -- Calculate summary totals
    calculateTotals = function(changes)
        local gains, losses = 0, 0
        for _, item in ipairs(changes) do
            if item.change > 0 then
                gains = gains + item.change
            else
                losses = losses + math.abs(item.change)
            end
        end
        return gains, losses
    end,

    formatChange = function(id, change)
        local color = change > 0 and colors.lime or colors.red
        local sign = change > 0 and "+" or ""
        return {
            lines = { Text.prettifyName(id), sign .. Text.formatNumber(change, 0) },
            colors = { colors.white, color }
        }
    end,

    -- Draw a progress bar showing time until reset
    -- @param monitor The monitor to draw on
    -- @param y Y position for the bar
    -- @param width Total width available
    -- @param elapsed Seconds elapsed
    -- @param total Total seconds in period
    drawTimerBar = function(monitor, y, width, elapsed, total)
        local progress = math.min(1, elapsed / total)
        local remaining = math.max(0, total - elapsed)

        -- Format remaining time
        local timeStr
        if remaining >= 3600 then
            timeStr = string.format("%dh%dm", math.floor(remaining / 3600), math.floor((remaining % 3600) / 60))
        elseif remaining >= 60 then
            timeStr = string.format("%dm%ds", math.floor(remaining / 60), remaining % 60)
        else
            timeStr = remaining .. "s"
        end

        -- Bar width (leave room for time text)
        local barWidth = math.max(4, width - #timeStr - 3)
        local filledWidth = math.floor(barWidth * progress)
        local emptyWidth = barWidth - filledWidth

        -- Draw bar background
        monitor.setCursorPos(1, y)
        monitor.setBackgroundColor(colors.gray)
        monitor.setTextColor(colors.white)

        -- Filled portion (shows progress toward reset)
        if filledWidth > 0 then
            monitor.setBackgroundColor(colors.blue)
            monitor.write(string.rep(" ", filledWidth))
        end

        -- Empty portion
        if emptyWidth > 0 then
            monitor.setBackgroundColor(colors.gray)
            monitor.write(string.rep(" ", emptyWidth))
        end

        -- Time text (right-aligned)
        monitor.setBackgroundColor(colors.black)
        monitor.setTextColor(colors.lightGray)
        monitor.setCursorPos(width - #timeStr + 1, y)
        monitor.write(timeStr)
    end,

    render = function(self)
        self.renderCount = self.renderCount + 1
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)

        -- Check interface
        if not self.interface then
            self.monitor.clear()
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No AE2 peripheral", colors.red)
            return
        end

        local now = os.epoch("utc")

        -- State machine
        if self.state == "init" then
            -- First render: take baseline and move to next state
            local snapshot, count, ok = module.takeSnapshot(self)
            if ok and count > 0 then
                self.baseline = module.copySnapshot(snapshot)
                self.baselineCount = count
                self.periodStart = now
                self.state = "baseline_set"

                -- Show initialization message (don't compare yet)
                self.monitor.clear()
                MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Item Changes", colors.white)
                MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Baseline captured: " .. count .. " items", colors.lime)

                -- Draw timer bar at bottom
                module.drawTimerBar(self.monitor, self.height, self.width, 0, self.periodSeconds)
                return
            else
                -- Failed to get data
                self.monitor.clear()
                MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Item Changes", colors.white)
                MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Waiting for AE2 data...", colors.gray)
                return
            end

        elseif self.state == "baseline_set" then
            -- Second render: now we can start tracking
            self.state = "tracking"
            -- Fall through to tracking logic
        end

        -- Check for period reset
        local elapsed = (now - self.periodStart) / 1000
        if elapsed >= self.periodSeconds then
            -- Period expired - take new baseline
            local snapshot, count, ok = module.takeSnapshot(self)
            if ok and count > 0 then
                self.baseline = module.copySnapshot(snapshot)
                self.baselineCount = count
                self.periodStart = now

                -- Show reset message
                self.monitor.clear()
                MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Period Reset", colors.orange)
                MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "New baseline: " .. count .. " items", colors.gray)

                -- Draw timer bar at bottom (just reset, so 0 elapsed)
                module.drawTimerBar(self.monitor, self.height, self.width, 0, self.periodSeconds)
                return
            end
        end

        -- Take current snapshot
        local current, itemCount, ok = module.takeSnapshot(self)
        if not ok then
            self.monitor.clear()
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "Error reading AE2", colors.red)
            return
        end

        -- Calculate changes from baseline
        local changes = module.calculateChanges(self, current)

        -- Calculate remaining time
        local remaining = math.max(0, math.floor(self.periodSeconds - elapsed))

        -- Handle no changes
        if #changes == 0 then
            self.monitor.clear()

            MonitorHelpers.writeCentered(self.monitor, 1, "Item Changes", colors.white)

            -- Center message
            local centerY = math.floor(self.height / 2)
            MonitorHelpers.writeCentered(self.monitor, centerY - 1, "No changes detected", colors.gray)

            -- Show baseline info
            local infoStr = "Baseline: " .. self.baselineCount .. " | Current: " .. itemCount
            MonitorHelpers.writeCentered(self.monitor, centerY + 1, Text.truncateMiddle(infoStr, self.width - 2), colors.lightGray)

            -- Draw timer bar at bottom
            module.drawTimerBar(self.monitor, self.height, self.width, elapsed, self.periodSeconds)

            return
        end

        -- Sort by absolute change descending
        table.sort(changes, function(a, b)
            return math.abs(a.change) > math.abs(b.change)
        end)

        -- Calculate totals
        local totalGains, totalLosses = module.calculateTotals(changes)

        -- Display items in grid
        self.display:display(changes, function(item)
            return module.formatChange(item.id, item.change)
        end)

        -- Draw header overlay
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setCursorPos(1, 1)
        self.monitor.clearLine()

        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(1, 1)
        self.monitor.write("Changes")

        self.monitor.setTextColor(colors.lightGray)
        self.monitor.write(" (" .. #changes .. ")")

        -- Time indicator
        local timeStr = remaining .. "s"
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(math.max(1, self.width - #timeStr + 1), 1)
        self.monitor.write(timeStr)

        -- Summary row
        if self.height >= 8 then
            self.monitor.setCursorPos(1, 2)
            self.monitor.clearLine()
            if totalGains > 0 then
                self.monitor.setTextColor(colors.lime)
                self.monitor.write("+" .. Text.formatNumber(totalGains, 0))
            end
            if totalLosses > 0 then
                if totalGains > 0 then
                    self.monitor.setTextColor(colors.gray)
                    self.monitor.write(" ")
                end
                self.monitor.setTextColor(colors.red)
                self.monitor.write("-" .. Text.formatNumber(totalLosses, 0))
            end
        end

        -- Draw timer bar at bottom
        module.drawTimerBar(self.monitor, self.height, self.width, elapsed, self.periodSeconds)

        self.monitor.setTextColor(colors.white)
    end
}

return module
