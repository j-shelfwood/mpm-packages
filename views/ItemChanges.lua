-- ItemChanges.lua
-- Tracks and displays inventory changes over a configurable time period
-- Compares current inventory against a baseline taken at period start
-- Refactored to use BaseView pattern

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local GridDisplay = mpm('utils/GridDisplay')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

-- Take a snapshot of current item counts
-- Returns: table {[registryName] = count}, itemCount, success
local function takeSnapshot(interface)
    if not interface then
        return {}, 0, false
    end

    local ok, items = pcall(function() return interface:items() end)
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
end

-- Deep copy a table (to prevent reference issues)
local function copySnapshot(snapshot)
    local copy = {}
    for k, v in pairs(snapshot) do
        copy[k] = v
    end
    return copy
end

-- Calculate changes between baseline and current
local function calculateChanges(baseline, current, showMode, minChange)
    local changes = {}

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
end

-- Calculate summary totals
local function calculateTotals(changes)
    local gains, losses = 0, 0
    for _, item in ipairs(changes) do
        if item.change > 0 then
            gains = gains + item.change
        else
            losses = losses + math.abs(item.change)
        end
    end
    return gains, losses
end

-- Format a change item for grid display
local function formatChange(item)
    local color = item.change > 0 and colors.lime or colors.red
    local sign = item.change > 0 and "+" or ""
    return {
        lines = { Text.prettifyName(item.id), sign .. Text.formatNumber(item.change, 0) },
        colors = { colors.white, color }
    }
end

-- Draw a progress bar showing time until reset
local function drawTimerBar(monitor, y, width, elapsed, total)
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
end

return BaseView.custom({
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

    mount = function()
        return AEInterface.exists()
    end,

    init = function(self, config)
        -- Try to connect to AE2 (protected)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil

        -- Config
        self.periodSeconds = config.periodSeconds or 60
        self.showMode = config.showMode or "both"
        self.minChange = config.minChange or 1

        -- Grid display
        self.display = GridDisplay.new(self.monitor)

        -- State machine: "init", "baseline_set", "tracking"
        self.state = "init"

        -- Baseline snapshot (frozen at period start)
        self.baseline = {}
        self.baselineCount = 0

        -- When the current tracking period started
        self.periodStart = 0

        -- Cached changes for current period
        self.cachedData = nil
        self.lastUpdate = 0
    end,

    getData = function(self)
        -- No interface available
        if not self.interface then
            return { error = "No AE2 peripheral" }
        end

        local now = os.epoch("utc")

        -- State: init - take initial baseline
        if self.state == "init" then
            local snapshot, count, ok = takeSnapshot(self.interface)
            if ok and count > 0 then
                self.baseline = copySnapshot(snapshot)
                self.baselineCount = count
                self.periodStart = now
                self.state = "baseline_set"
                self.cachedData = nil
                self.lastUpdate = 0
                return {
                    status = "baseline_captured",
                    baselineCount = count,
                    elapsed = 0
                }
            else
                return { status = "waiting" }
            end
        end

        -- State: baseline_set - transition to tracking
        if self.state == "baseline_set" then
            self.state = "tracking"
        end

        -- Calculate elapsed time
        local elapsed = (now - self.periodStart) / 1000

        -- Check for period reset
        if elapsed >= self.periodSeconds then
            local snapshot, count, ok = takeSnapshot(self.interface)
            if ok and count > 0 then
                self.baseline = copySnapshot(snapshot)
                self.baselineCount = count
                self.periodStart = now
                self.cachedData = nil
                self.lastUpdate = 0
                return {
                    status = "period_reset",
                    baselineCount = count,
                    elapsed = 0
                }
            end
        end

        -- Reuse cached changes during the period
        if self.cachedData and self.lastUpdate >= self.periodStart then
            return {
                status = "tracking",
                changes = self.cachedData.changes,
                totalGains = self.cachedData.totalGains,
                totalLosses = self.cachedData.totalLosses,
                baselineCount = self.baselineCount,
                currentCount = self.cachedData.currentCount,
                elapsed = elapsed
            }
        end

        -- Take current snapshot
        local current, itemCount, ok = takeSnapshot(self.interface)
        if not ok then
            return { error = "Error reading AE2" }
        end

        -- Calculate changes from baseline
        local changes = calculateChanges(self.baseline, current, self.showMode, self.minChange)

        -- Sort by absolute change descending
        table.sort(changes, function(a, b)
            return math.abs(a.change) > math.abs(b.change)
        end)

        -- Calculate totals
        local totalGains, totalLosses = calculateTotals(changes)

        self.cachedData = {
            changes = changes,
            totalGains = totalGains,
            totalLosses = totalLosses,
            currentCount = itemCount
        }
        self.lastUpdate = now

        return {
            status = "tracking",
            changes = changes,
            totalGains = totalGains,
            totalLosses = totalLosses,
            baselineCount = self.baselineCount,
            currentCount = itemCount,
            elapsed = elapsed
        }
    end,

    render = function(self, data)
        -- Handle error states
        if data.error then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), data.error, colors.red)
            return
        end

        -- Handle waiting state
        if data.status == "waiting" then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Item Changes", colors.white)
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Waiting for AE2 data...", colors.gray)
            return
        end

        -- Handle baseline captured state
        if data.status == "baseline_captured" then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Item Changes", colors.white)
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Baseline captured: " .. data.baselineCount .. " items", colors.lime)
            drawTimerBar(self.monitor, self.height, self.width, 0, self.periodSeconds)
            return
        end

        -- Handle period reset state
        if data.status == "period_reset" then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Period Reset", colors.orange)
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "New baseline: " .. data.baselineCount .. " items", colors.gray)
            drawTimerBar(self.monitor, self.height, self.width, 0, self.periodSeconds)
            return
        end

        -- Tracking state - show changes
        local changes = data.changes or {}
        local remaining = math.max(0, math.floor(self.periodSeconds - data.elapsed))

        -- Handle no changes
        if #changes == 0 then
            MonitorHelpers.writeCentered(self.monitor, 1, "Item Changes", colors.white)

            local centerY = math.floor(self.height / 2)
            MonitorHelpers.writeCentered(self.monitor, centerY - 1, "No changes detected", colors.gray)

            local infoStr = "Baseline: " .. data.baselineCount .. " | Current: " .. data.currentCount
            MonitorHelpers.writeCentered(self.monitor, centerY + 1, Text.truncateMiddle(infoStr, self.width - 2), colors.lightGray)

            drawTimerBar(self.monitor, self.height, self.width, data.elapsed, self.periodSeconds)
            return
        end

        -- Display items in grid
        self.display:display(changes, formatChange)

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
            if data.totalGains > 0 then
                self.monitor.setTextColor(colors.lime)
                self.monitor.write("+" .. Text.formatNumber(data.totalGains, 0))
            end
            if data.totalLosses > 0 then
                if data.totalGains > 0 then
                    self.monitor.setTextColor(colors.gray)
                    self.monitor.write(" ")
                end
                self.monitor.setTextColor(colors.red)
                self.monitor.write("-" .. Text.formatNumber(data.totalLosses, 0))
            end
        end

        -- Draw timer bar at bottom
        drawTimerBar(self.monitor, self.height, self.width, data.elapsed, self.periodSeconds)

        self.monitor.setTextColor(colors.white)
    end,

    errorMessage = "Error tracking changes"
})
