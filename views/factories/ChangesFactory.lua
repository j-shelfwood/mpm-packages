-- ChangesFactory.lua
-- Factory for generating resource change tracking views
-- Creates Item/Fluid/ChemicalChanges with configurable data source

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local GridDisplay = mpm('utils/GridDisplay')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Core = mpm('ui/Core')
local Yield = mpm('utils/Yield')

local ChangesFactory = {}

-- Take a snapshot of current resource amounts
-- @param interface AE interface
-- @param dataMethod Method name to call (items/fluids/chemicals)
-- @param idField Field name for resource ID (registryName/name)
-- @param amountField Field name for amount (count/amount)
-- @return snapshot table, count, success
local function takeSnapshot(interface, dataMethod, idField, amountField)
    if not interface then
        return {}, 0, false
    end

    local ok, resources = pcall(function() return interface[dataMethod](interface) end)
    if not ok or not resources or #resources == 0 then
        return {}, 0, false
    end

    Yield.yield()

    local snapshot = {}
    local count = 0

    for _, resource in ipairs(resources) do
        local id = resource[idField]
        if id then
            local amount = resource[amountField] or resource.count or resource.amount or 0
            if amount > 0 then
                snapshot[id] = (snapshot[id] or 0) + amount
                count = count + 1
            end
        end
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

    local seen = {}

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
    for _, resource in ipairs(changes) do
        if resource.change > 0 then
            gains = gains + resource.change
        else
            losses = losses + math.abs(resource.change)
        end
    end
    return gains, losses
end

-- Draw timer bar at bottom
local function drawTimerBar(monitor, y, width, elapsed, total, barColor)
    local progress = math.min(1, elapsed / total)
    local remaining = math.max(0, total - elapsed)

    local timeStr
    if remaining >= 3600 then
        timeStr = string.format("%dh%dm", math.floor(remaining / 3600), math.floor((remaining % 3600) / 60))
    elseif remaining >= 60 then
        timeStr = string.format("%dm%ds", math.floor(remaining / 60), remaining % 60)
    else
        timeStr = remaining .. "s"
    end

    local barWidth = math.max(4, width - #timeStr - 3)
    local filledWidth = math.floor(barWidth * progress)
    local emptyWidth = barWidth - filledWidth

    monitor.setCursorPos(1, y)
    monitor.setBackgroundColor(colors.gray)
    monitor.setTextColor(colors.white)

    if filledWidth > 0 then
        monitor.setBackgroundColor(barColor)
        monitor.write(string.rep(" ", filledWidth))
    end

    if emptyWidth > 0 then
        monitor.setBackgroundColor(colors.gray)
        monitor.write(string.rep(" ", emptyWidth))
    end

    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.lightGray)
    monitor.setCursorPos(width - #timeStr + 1, y)
    monitor.write(timeStr)
end

-- Show resource detail overlay
local function showResourceDetail(self, resource, config)
    local monitor = self.monitor
    local width, height = monitor.getSize()

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
        local titleColor = resource.change > 0 and colors.lime or colors.red
        monitor.setBackgroundColor(titleColor)
        monitor.setTextColor(colors.black)
        monitor.setCursorPos(x1, y1)
        monitor.write(string.rep(" ", overlayWidth))
        monitor.setCursorPos(x1 + 1, y1)
        local sign = resource.change > 0 and "+" or ""
        local displayChange = resource.change / config.unitDivisor
        monitor.write(Core.truncate(sign .. Text.formatNumber(displayChange, 1) .. config.unitLabel, overlayWidth - 2))

        -- Content
        monitor.setBackgroundColor(colors.gray)
        local contentY = y1 + 2

        -- Resource name
        local resourceName = Text.prettifyName(resource.id)
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.write(Core.truncate(resourceName, overlayWidth - 2))
        contentY = contentY + 1

        -- Registry name
        monitor.setTextColor(colors.lightGray)
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.write(Core.truncate(resource.id, overlayWidth - 2))
        contentY = contentY + 2

        -- Baseline → Current
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.write("Was: ")
        monitor.setTextColor(colors.yellow)
        monitor.write(Text.formatNumber(resource.baseline / config.unitDivisor, 1) .. config.unitLabel)
        monitor.setTextColor(colors.gray)
        monitor.write(" -> ")
        monitor.setTextColor(config.accentColor)
        monitor.write(Text.formatNumber(resource.current / config.unitDivisor, 1) .. config.unitLabel)

        -- Close button
        local buttonY = y2 - 1
        monitor.setBackgroundColor(colors.gray)
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(x1 + math.floor((overlayWidth - 7) / 2), buttonY)
        monitor.write("[Close]")

        Core.resetColors(monitor)

        local event, side, tx, ty = os.pullEvent("monitor_touch")

        if side == monitorName then
            return
        end
    end
end

-- Create a Changes view with the given configuration
-- @param config Table:
--   name: View name for display (e.g., "Item", "Fluid", "Chemical")
--   dataMethod: AEInterface method (e.g., "items", "fluids", "chemicals")
--   idField: Field name for resource ID (e.g., "registryName", "name")
--   amountField: Field name for amount (e.g., "count", "amount")
--   unitDivisor: Divide amounts for display (1 for items, 1000 for fluids/chemicals)
--   unitLabel: Unit suffix (e.g., "", "B")
--   titleColor: Header color
--   barColor: Timer bar color
--   accentColor: Accent color for amounts
--   defaultMinChange: Default minimum change threshold
--   mountCheck: Optional function to check if view can mount
-- @return View definition table
function ChangesFactory.create(config)
    config = config or {}
    config.name = config.name or "Resource"
    config.dataMethod = config.dataMethod or "items"
    config.idField = config.idField or "registryName"
    config.amountField = config.amountField or "count"
    config.unitDivisor = config.unitDivisor or 1
    config.unitLabel = config.unitLabel or ""
    config.titleColor = config.titleColor or colors.white
    config.barColor = config.barColor or colors.blue
    config.accentColor = config.accentColor or colors.cyan
    config.defaultMinChange = config.defaultMinChange or 1

    -- Format function for grid display
    local function formatChange(resource)
        local color = resource.change > 0 and colors.lime or colors.red
        local sign = resource.change > 0 and "+" or ""
        local displayChange = resource.change / config.unitDivisor
        return {
            lines = { Text.prettifyName(resource.id), sign .. Text.formatNumber(displayChange, 1) .. config.unitLabel },
            colors = { colors.white, color }
        }
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
                default = config.defaultMinChange,
                min = 1,
                max = 100000,
                presets = config.unitDivisor > 1 and {100, 1000, 5000, 10000} or {1, 10, 50, 100}
            }
        },

        mount = function()
            if config.mountCheck then
                return config.mountCheck()
            end
            return AEInterface.exists()
        end,

        init = function(self, viewConfig)
            local ok, interface = pcall(AEInterface.new)
            self.interface = ok and interface or nil

            self.periodSeconds = viewConfig.periodSeconds or 60
            self.showMode = viewConfig.showMode or "both"
            self.minChange = viewConfig.minChange or config.defaultMinChange

            self.display = GridDisplay.new(self.monitor)

            self.state = "init"
            self.baseline = {}
            self.baselineCount = 0
            self.periodStart = 0
            self.cachedData = nil
            self.lastUpdate = 0
            self.lastChanges = {}
            self.factoryConfig = config
        end,

        getData = function(self)
            if not self.interface then
                return { error = "No AE2 peripheral" }
            end

            if config.mountCheck and not config.mountCheck() then
                return { error = config.name .. " not available" }
            end

            local now = os.epoch("utc")

            -- State: init
            if self.state == "init" then
                local snapshot, count, ok = takeSnapshot(self.interface, config.dataMethod, config.idField, config.amountField)
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

            if self.state == "baseline_set" then
                self.state = "tracking"
            end

            local elapsed = (now - self.periodStart) / 1000

            -- Period reset
            if elapsed >= self.periodSeconds then
                local snapshot, count, ok = takeSnapshot(self.interface, config.dataMethod, config.idField, config.amountField)
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

            -- Use cached data
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
            local current, resourceCount, ok = takeSnapshot(self.interface, config.dataMethod, config.idField, config.amountField)
            if not ok then
                return { error = "Error reading " .. config.name:lower() .. "s" }
            end

            local changes = calculateChanges(self.baseline, current, self.showMode, self.minChange)

            table.sort(changes, function(a, b)
                return math.abs(a.change) > math.abs(b.change)
            end)

            local totalGains, totalLosses = calculateTotals(changes)

            self.cachedData = {
                changes = changes,
                totalGains = totalGains,
                totalLosses = totalLosses,
                currentCount = resourceCount
            }
            self.lastUpdate = now

            return {
                status = "tracking",
                changes = changes,
                totalGains = totalGains,
                totalLosses = totalLosses,
                baselineCount = self.baselineCount,
                currentCount = resourceCount,
                elapsed = elapsed
            }
        end,

        render = function(self, data)
            local cfg = self.factoryConfig

            -- Handle errors
            if data.error then
                MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), data.error, colors.red)
                return
            end

            -- Waiting state
            if data.status == "waiting" then
                MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, cfg.name .. " Changes", colors.white)
                MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Waiting for data...", colors.gray)
                return
            end

            -- Baseline captured
            if data.status == "baseline_captured" then
                MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, cfg.name .. " Changes", colors.white)
                MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Baseline: " .. data.baselineCount .. " " .. cfg.name:lower() .. "s", colors.lime)
                drawTimerBar(self.monitor, self.height, self.width, 0, self.periodSeconds, cfg.barColor)
                return
            end

            -- Period reset
            if data.status == "period_reset" then
                MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Period Reset", colors.orange)
                MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "New baseline: " .. data.baselineCount .. " " .. cfg.name:lower() .. "s", colors.gray)
                drawTimerBar(self.monitor, self.height, self.width, 0, self.periodSeconds, cfg.barColor)
                return
            end

            -- Tracking state
            local changes = data.changes or {}
            local remaining = math.max(0, math.floor(self.periodSeconds - data.elapsed))

            -- No changes
            if #changes == 0 then
                MonitorHelpers.writeCentered(self.monitor, 1, cfg.name .. " Changes", cfg.titleColor)
                local centerY = math.floor(self.height / 2)
                MonitorHelpers.writeCentered(self.monitor, centerY - 1, "No changes detected", colors.gray)
                local infoStr = "Baseline: " .. data.baselineCount .. " | Current: " .. data.currentCount
                MonitorHelpers.writeCentered(self.monitor, centerY + 1, Text.truncateMiddle(infoStr, self.width - 2), colors.lightGray)
                drawTimerBar(self.monitor, self.height, self.width, data.elapsed, self.periodSeconds, cfg.barColor)
                return
            end

            -- Display in grid
            self.display:display(changes, formatChange)

            -- Header overlay
            self.monitor.setBackgroundColor(colors.black)
            self.monitor.setCursorPos(1, 1)
            self.monitor.clearLine()

            self.monitor.setTextColor(cfg.titleColor)
            self.monitor.setCursorPos(1, 1)
            self.monitor.write(cfg.name .. "s")

            self.monitor.setTextColor(colors.lightGray)
            self.monitor.write(" (" .. #changes .. ")")

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
                    self.monitor.write("+" .. Text.formatNumber(data.totalGains / cfg.unitDivisor, 1) .. cfg.unitLabel)
                end
                if data.totalLosses > 0 then
                    if data.totalGains > 0 then
                        self.monitor.setTextColor(colors.gray)
                        self.monitor.write(" ")
                    end
                    self.monitor.setTextColor(colors.red)
                    self.monitor.write("-" .. Text.formatNumber(data.totalLosses / cfg.unitDivisor, 1) .. cfg.unitLabel)
                end
            end

            drawTimerBar(self.monitor, self.height, self.width, data.elapsed, self.periodSeconds, cfg.barColor)

            self.lastChanges = changes

            self.monitor.setTextColor(colors.white)
        end,

        onTouch = function(self, x, y)
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
                    showResourceDetail(self, self.lastChanges[index], self.factoryConfig)
                    return true
                end
            end

            return false
        end,

        errorMessage = "Error tracking changes"
    })
end

return ChangesFactory
