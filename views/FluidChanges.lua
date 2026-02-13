-- FluidChanges.lua
-- Tracks and displays fluid changes over a configurable time period
-- Compares current fluids against a baseline taken at period start
-- Analogous to ItemChanges but for fluids

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local GridDisplay = mpm('utils/GridDisplay')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Core = mpm('ui/Core')
local Yield = mpm('utils/Yield')

-- Take a snapshot of current fluid amounts
-- Returns: table {[registryName] = amount}, fluidCount, success
local function takeSnapshot(interface)
    if not interface then
        return {}, 0, false
    end

    local ok, fluids = pcall(function() return interface:fluids() end)
    if not ok or not fluids or #fluids == 0 then
        return {}, 0, false
    end

    Yield.yield()

    local snapshot = {}
    local count = 0

    for _, fluid in ipairs(fluids) do
        if fluid.registryName then
            local amount = fluid.amount or 0
            if amount > 0 then
                snapshot[fluid.registryName] = (snapshot[fluid.registryName] or 0) + amount
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

-- Deep copy a table
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

    -- Track which baseline fluids we've seen
    local seen = {}

    -- Check current fluids against baseline
    for id, currAmount in pairs(current) do
        seen[id] = true
        local baseAmount = baseline[id] or 0
        local change = currAmount - baseAmount

        if change ~= 0 and math.abs(change) >= minChange then
            local include = (showMode == "both") or
                (showMode == "gains" and change > 0) or
                (showMode == "losses" and change < 0)

            if include then
                table.insert(changes, {
                    id = id,
                    change = change,
                    current = currAmount,
                    baseline = baseAmount
                })
            end
        end
    end

    -- Check for fluids completely removed
    for id, baseAmount in pairs(baseline) do
        if not seen[id] and baseAmount > 0 then
            local change = -baseAmount
            if math.abs(change) >= minChange then
                local include = (showMode == "both") or (showMode == "losses")
                if include then
                    table.insert(changes, {
                        id = id,
                        change = change,
                        current = 0,
                        baseline = baseAmount
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
    for _, fluid in ipairs(changes) do
        if fluid.change > 0 then
            gains = gains + fluid.change
        else
            losses = losses + math.abs(fluid.change)
        end
    end
    return gains, losses
end

-- Format a change for grid display (amounts in buckets)
local function formatChange(fluid)
    local color = fluid.change > 0 and colors.lime or colors.red
    local sign = fluid.change > 0 and "+" or ""
    local buckets = fluid.change / 1000
    return {
        lines = { Text.prettifyName(fluid.id), sign .. Text.formatNumber(buckets, 1) .. "B" },
        colors = { colors.white, color }
    }
end

-- Show fluid detail overlay (blocking)
local function showFluidDetail(self, fluid)
    local monitor = self.monitor
    local width, height = monitor.getSize()

    -- Calculate overlay bounds
    local overlayWidth = math.min(width - 2, 28)
    local overlayHeight = math.min(height - 2, 8)
    local x1 = math.floor((width - overlayWidth) / 2) + 1
    local y1 = math.floor((height - overlayHeight) / 2) + 1
    local x2 = x1 + overlayWidth - 1
    local y2 = y1 + overlayHeight - 1

    local monitorName = self.peripheralName

    while true do
        -- Draw background
        monitor.setBackgroundColor(colors.gray)
        for y = y1, y2 do
            monitor.setCursorPos(x1, y)
            monitor.write(string.rep(" ", overlayWidth))
        end

        -- Title bar
        local titleColor = fluid.change > 0 and colors.lime or colors.red
        monitor.setBackgroundColor(titleColor)
        monitor.setTextColor(colors.black)
        monitor.setCursorPos(x1, y1)
        monitor.write(string.rep(" ", overlayWidth))
        monitor.setCursorPos(x1 + 1, y1)
        local sign = fluid.change > 0 and "+" or ""
        local buckets = fluid.change / 1000
        monitor.write(Core.truncate(sign .. Text.formatNumber(buckets, 1) .. "B", overlayWidth - 2))

        -- Content
        monitor.setBackgroundColor(colors.gray)
        local contentY = y1 + 2

        -- Fluid name
        local fluidName = Text.prettifyName(fluid.id)
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.write(Core.truncate(fluidName, overlayWidth - 2))
        contentY = contentY + 1

        -- Registry name
        monitor.setTextColor(colors.lightGray)
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.write(Core.truncate(fluid.id, overlayWidth - 2))
        contentY = contentY + 2

        -- Baseline → Current
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.write("Was: ")
        monitor.setTextColor(colors.yellow)
        monitor.write(Text.formatNumber(fluid.baseline / 1000, 1) .. "B")
        monitor.setTextColor(colors.gray)
        monitor.write(" -> ")
        monitor.setTextColor(colors.cyan)
        monitor.write(Text.formatNumber(fluid.current / 1000, 1) .. "B")

        -- Close button
        local buttonY = y2 - 1
        monitor.setBackgroundColor(colors.gray)
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(x1 + math.floor((overlayWidth - 7) / 2), buttonY)
        monitor.write("[Close]")

        Core.resetColors(monitor)

        -- Wait for touch
        local event, side, tx, ty = os.pullEvent("monitor_touch")

        if side == monitorName then
            -- Any touch closes
            return
        end
    end
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

    -- Bar width
    local barWidth = math.max(4, width - #timeStr - 3)
    local filledWidth = math.floor(barWidth * progress)
    local emptyWidth = barWidth - filledWidth

    -- Draw bar
    monitor.setCursorPos(1, y)
    monitor.setBackgroundColor(colors.gray)
    monitor.setTextColor(colors.white)

    if filledWidth > 0 then
        monitor.setBackgroundColor(colors.cyan)
        monitor.write(string.rep(" ", filledWidth))
    end

    if emptyWidth > 0 then
        monitor.setBackgroundColor(colors.gray)
        monitor.write(string.rep(" ", emptyWidth))
    end

    -- Time text
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
            label = "Min Change (mB)",
            default = 1000,
            min = 1,
            max = 100000,
            presets = {100, 1000, 5000, 10000}
        }
    },

    mount = function()
        return AEInterface.exists()
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil

        self.periodSeconds = config.periodSeconds or 60
        self.showMode = config.showMode or "both"
        self.minChange = config.minChange or 1000

        self.display = GridDisplay.new(self.monitor)

        self.state = "init"
        self.baseline = {}
        self.baselineCount = 0
        self.periodStart = 0
        self.cachedData = nil
        self.lastUpdate = 0
        self.lastChanges = {}
    end,

    getData = function(self)
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

        -- Reuse cached changes
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
        local current, fluidCount, ok = takeSnapshot(self.interface)
        if not ok then
            return { error = "Error reading AE2" }
        end

        -- Calculate changes
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
            currentCount = fluidCount
        }
        self.lastUpdate = now

        return {
            status = "tracking",
            changes = changes,
            totalGains = totalGains,
            totalLosses = totalLosses,
            baselineCount = self.baselineCount,
            currentCount = fluidCount,
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
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Fluid Changes", colors.white)
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Waiting for AE2 data...", colors.gray)
            return
        end

        -- Handle baseline captured
        if data.status == "baseline_captured" then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Fluid Changes", colors.white)
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Baseline: " .. data.baselineCount .. " fluids", colors.lime)
            drawTimerBar(self.monitor, self.height, self.width, 0, self.periodSeconds)
            return
        end

        -- Handle period reset
        if data.status == "period_reset" then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Period Reset", colors.orange)
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "New baseline: " .. data.baselineCount .. " fluids", colors.gray)
            drawTimerBar(self.monitor, self.height, self.width, 0, self.periodSeconds)
            return
        end

        -- Tracking state
        local changes = data.changes or {}
        local remaining = math.max(0, math.floor(self.periodSeconds - data.elapsed))

        -- Handle no changes
        if #changes == 0 then
            MonitorHelpers.writeCentered(self.monitor, 1, "Fluid Changes", colors.cyan)
            local centerY = math.floor(self.height / 2)
            MonitorHelpers.writeCentered(self.monitor, centerY - 1, "No changes detected", colors.gray)
            local infoStr = "Baseline: " .. data.baselineCount .. " | Current: " .. data.currentCount
            MonitorHelpers.writeCentered(self.monitor, centerY + 1, Text.truncateMiddle(infoStr, self.width - 2), colors.lightGray)
            drawTimerBar(self.monitor, self.height, self.width, data.elapsed, self.periodSeconds)
            return
        end

        -- Display fluids in grid
        self.display:display(changes, formatChange)

        -- Draw header overlay
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setCursorPos(1, 1)
        self.monitor.clearLine()

        self.monitor.setTextColor(colors.cyan)
        self.monitor.setCursorPos(1, 1)
        self.monitor.write("Fluids")

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
                self.monitor.write("+" .. Text.formatNumber(data.totalGains / 1000, 1) .. "B")
            end
            if data.totalLosses > 0 then
                if data.totalGains > 0 then
                    self.monitor.setTextColor(colors.gray)
                    self.monitor.write(" ")
                end
                self.monitor.setTextColor(colors.red)
                self.monitor.write("-" .. Text.formatNumber(data.totalLosses / 1000, 1) .. "B")
            end
        end

        -- Draw timer bar at bottom
        drawTimerBar(self.monitor, self.height, self.width, data.elapsed, self.periodSeconds)

        -- Store changes for touch lookup
        self.lastChanges = changes

        self.monitor.setTextColor(colors.white)
    end,

    onTouch = function(self, x, y)
        -- Find which fluid was touched based on grid position
        if #self.lastChanges == 0 then
            return false
        end

        local itemsPerRow = math.floor(self.width / 12)
        if itemsPerRow < 1 then itemsPerRow = 1 end

        local startY = 3
        local itemHeight = 2
        local itemWidth = math.floor(self.width / itemsPerRow)

        if y >= startY and y < self.height then
            local row = math.floor((y - startY) / itemHeight)
            local col = math.floor((x - 1) / itemWidth)
            local index = row * itemsPerRow + col + 1

            if index >= 1 and index <= #self.lastChanges then
                showFluidDetail(self, self.lastChanges[index])
                return true
            end
        end

        return false
    end,

    errorMessage = "Error tracking fluid changes"
})
