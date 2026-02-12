-- ItemChanges.lua
-- Tracks and displays inventory changes over a configurable time period
-- Shows items gained or lost since the tracking period began
-- Fully rewritten for reliability on large AE2 systems

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
            default = 1800,
            min = 60,
            max = 86400,
            presets = {60, 300, 600, 1800, 3600}
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
            periodSeconds = config.periodSeconds or 1800,
            showMode = config.showMode or "both",
            minChange = config.minChange or 1,
            interface = nil,
            display = GridDisplay.new(monitor),
            -- Baseline snapshot taken at start of tracking period
            baseline = nil,
            -- When the current tracking period started
            periodStart = nil,
            -- Last known item counts (for detecting changes between renders)
            lastSnapshot = nil,
            -- Accumulated changes from baseline
            changes = {},
            -- Stats
            totalGains = 0,
            totalLosses = 0,
            initialized = false
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
    -- Returns: table {[registryName] = count}, totalItems
    takeSnapshot = function(self)
        if not self.interface then
            return nil, 0
        end

        local ok, items = pcall(function() return self.interface:items() end)
        if not ok or not items then
            return nil, 0
        end

        Yield.yield()

        local snapshot = {}
        local total = 0
        Yield.forEach(items, function(item)
            if item.registryName and item.count then
                snapshot[item.registryName] = (snapshot[item.registryName] or 0) + item.count
                total = total + 1
            end
        end)

        return snapshot, total
    end,

    -- Calculate changes between baseline and current snapshot
    -- Returns: array of {id, change, name}
    calculateChanges = function(self, current)
        if not self.baseline or not current then
            return {}
        end

        local changes = {}
        local showMode = self.showMode
        local minChange = self.minChange

        -- Check items in current snapshot
        local count = 0
        for id, currCount in pairs(current) do
            local baseCount = self.baseline[id] or 0
            local change = currCount - baseCount

            if math.abs(change) >= minChange then
                local include = false
                if showMode == "both" then
                    include = true
                elseif showMode == "gains" and change > 0 then
                    include = true
                elseif showMode == "losses" and change < 0 then
                    include = true
                end

                if include then
                    table.insert(changes, {
                        id = id,
                        change = change,
                        current = currCount
                    })
                end
            end

            count = count + 1
            Yield.check(count)
        end

        -- Check for items that were in baseline but not in current (fully consumed)
        count = 0
        for id, baseCount in pairs(self.baseline) do
            if not current[id] and baseCount > 0 then
                local change = -baseCount
                if math.abs(change) >= minChange then
                    local include = false
                    if showMode == "both" or showMode == "losses" then
                        include = true
                    end

                    if include then
                        table.insert(changes, {
                            id = id,
                            change = change,
                            current = 0
                        })
                    end
                end
            end
            count = count + 1
            Yield.check(count)
        end

        return changes
    end,

    -- Calculate totals for display
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

    render = function(self)
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)

        -- Check interface
        if not self.interface then
            self.monitor.clear()
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No AE2 peripheral", colors.red)
            return
        end

        local now = os.epoch("utc")

        -- Check if we need to start a new tracking period
        local needsReset = false
        if not self.periodStart then
            needsReset = true
        elseif (now - self.periodStart) / 1000 >= self.periodSeconds then
            needsReset = true
        end

        if needsReset then
            -- Take new baseline snapshot
            local snapshot, count = module.takeSnapshot(self)
            if snapshot and count > 0 then
                self.baseline = snapshot
                self.periodStart = now
                self.changes = {}
                self.lastSnapshot = snapshot
            elseif not self.baseline then
                -- First run and failed to get snapshot
                self.monitor.clear()
                MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Item Changes", colors.white)
                MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Waiting for data...", colors.gray)
                return
            end
        end

        -- Take current snapshot
        local current, itemCount = module.takeSnapshot(self)
        if not current then
            MonitorHelpers.writeCentered(self.monitor, 1, "Error fetching items", colors.red)
            return
        end

        -- Calculate changes from baseline
        local changes = module.calculateChanges(self, current)
        self.lastSnapshot = current

        -- Calculate elapsed and remaining time
        local elapsed = math.floor((now - self.periodStart) / 1000)
        local remaining = math.max(0, self.periodSeconds - elapsed)

        -- Handle no changes
        if #changes == 0 then
            self.monitor.clear()

            -- Title
            MonitorHelpers.writeCentered(self.monitor, 1, "Item Changes", colors.white)

            -- Time indicator
            local timeStr = remaining .. "s"
            self.monitor.setTextColor(colors.gray)
            self.monitor.setCursorPos(math.max(1, self.width - #timeStr + 1), 1)
            self.monitor.write(timeStr)

            -- Center message
            local centerY = math.floor(self.height / 2)
            MonitorHelpers.writeCentered(self.monitor, centerY - 1, "No changes detected", colors.gray)

            -- Show tracking info
            local trackingStr = "Tracking " .. itemCount .. " items"
            MonitorHelpers.writeCentered(self.monitor, centerY + 1, trackingStr, colors.lightGray)

            -- Mode indicator at bottom
            local modeStr = "Mode: " .. self.showMode
            if self.minChange > 1 then
                modeStr = modeStr .. " (min " .. self.minChange .. ")"
            end
            self.monitor.setTextColor(colors.gray)
            self.monitor.setCursorPos(1, self.height)
            self.monitor.write(Text.truncateMiddle(modeStr, self.width))

            return
        end

        -- Sort by absolute change descending
        table.sort(changes, function(a, b)
            return math.abs(a.change) > math.abs(b.change)
        end)

        -- Calculate totals
        local totalGains, totalLosses = module.calculateTotals(changes)

        -- Display items in grid (this clears the monitor)
        self.display:display(changes, function(item)
            return module.formatChange(item.id, item.change)
        end)

        -- Draw header OVER the grid (row 1)
        -- This works because header is short and grid is centered
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setCursorPos(1, 1)
        self.monitor.clearLine()

        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(1, 1)
        self.monitor.write("Changes")

        -- Show count
        self.monitor.setTextColor(colors.lightGray)
        self.monitor.write(" (" .. #changes .. ")")

        -- Time indicator
        local timeStr = remaining .. "s"
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(math.max(1, self.width - #timeStr + 1), 1)
        self.monitor.write(timeStr)

        -- Row 2: Summary (if room and not overlapping grid)
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

        self.monitor.setTextColor(colors.white)
    end
}

return module
