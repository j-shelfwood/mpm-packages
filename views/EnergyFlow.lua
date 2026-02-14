-- EnergyFlow.lua
-- Energy flow monitoring using Advanced Peripherals Energy Detector
-- Shows power throughput (FE/t) through detector blocks

local BaseView = mpm('views/BaseView')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

-- Find all energy detectors
local function findDetectors()
    local detectors = {}
    local names = peripheral.getNames()

    for _, name in ipairs(names) do
        local pType = peripheral.getType(name)
        if pType == "energy_detector" then
            table.insert(detectors, {
                peripheral = peripheral.wrap(name),
                name = name
            })
        end
    end

    return detectors
end

-- Get detector options for config
local function getDetectorOptions()
    local detectors = findDetectors()
    local options = {}

    if #detectors > 1 then
        table.insert(options, { value = "all", label = "All Detectors (" .. #detectors .. ")" })
    end

    for _, det in ipairs(detectors) do
        local shortName = det.name:match("_(%d+)$") or det.name
        table.insert(options, {
            value = det.name,
            label = "Detector " .. shortName
        })
    end

    return options
end

-- Format rate for display
local function formatRate(fePerTick)
    if fePerTick >= 1e9 then
        return string.format("%.2fGFE/t", fePerTick / 1e9)
    elseif fePerTick >= 1e6 then
        return string.format("%.2fMFE/t", fePerTick / 1e6)
    elseif fePerTick >= 1e3 then
        return string.format("%.1fkFE/t", fePerTick / 1e3)
    else
        return string.format("%.0fFE/t", fePerTick)
    end
end

return BaseView.custom({
    sleepTime = 0.5,  -- Fast updates for flow monitoring

    configSchema = {
        {
            key = "detector",
            type = "select",
            label = "Detector",
            options = getDetectorOptions,
            default = "all"
        },
        {
            key = "show_history",
            type = "select",
            label = "Show History",
            options = function()
                return {
                    { value = "yes", label = "Yes (Graph)" },
                    { value = "no", label = "No (Current Only)" }
                }
            end,
            default = "yes"
        }
    },

    mount = function()
        local detectors = findDetectors()
        return #detectors > 0
    end,

    init = function(self, config)
        self.detectorFilter = config.detector or "all"
        self.showHistory = config.show_history ~= "no"
        self.history = {}  -- { [detectorName] = { rate1, rate2, ... } }
        self.maxHistory = 60  -- 60 samples = 30 seconds at 0.5s interval
    end,

    getData = function(self)
        local detectors = findDetectors()
        local data = {
            detectors = {},
            totalRate = 0,
            totalLimit = 0
        }

        for idx, det in ipairs(detectors) do
            if self.detectorFilter == "all" or det.name == self.detectorFilter then
                local p = det.peripheral

                local rateOk, rate = pcall(p.getTransferRate)
                local limitOk, limit = pcall(p.getTransferRateLimit)

                rate = rateOk and rate or 0
                limit = limitOk and limit or 0

                -- Update history
                if not self.history[det.name] then
                    self.history[det.name] = {}
                end
                table.insert(self.history[det.name], rate)
                if #self.history[det.name] > self.maxHistory then
                    table.remove(self.history[det.name], 1)
                end

                -- Calculate stats
                local history = self.history[det.name]
                local sum = 0
                local max = 0
                for _, r in ipairs(history) do
                    sum = sum + r
                    if r > max then max = r end
                end
                local avg = #history > 0 and (sum / #history) or 0

                local shortName = det.name:match("_(%d+)$") or det.name

                table.insert(data.detectors, {
                    name = det.name,
                    shortName = shortName,
                    rate = rate,
                    limit = limit,
                    usage = limit > 0 and (rate / limit) or 0,
                    average = avg,
                    peak = max,
                    history = history
                })

                data.totalRate = data.totalRate + rate
                data.totalLimit = data.totalLimit + limit
            end
            Yield.check(idx, 5)
        end

        return data
    end,

    render = function(self, data)
        if #data.detectors == 0 then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No detectors found", colors.orange)
            return
        end

        -- Single detector mode
        if #data.detectors == 1 then
            self:renderSingle(data.detectors[1])
        else
            self:renderMultiple(data)
        end
    end,

    renderSingle = function(self, detector)
        -- Title
        MonitorHelpers.writeCentered(self.monitor, 1, "Energy Flow", colors.yellow)

        -- Current rate (big)
        local rateStr = formatRate(detector.rate)
        self.monitor.setTextColor(colors.white)
        MonitorHelpers.writeCentered(self.monitor, 3, rateStr, colors.white)

        -- Usage bar
        local barWidth = self.width - 4
        local barX = 3
        local barY = 5

        local usageColor = colors.green
        if detector.usage > 0.9 then
            usageColor = colors.red
        elseif detector.usage > 0.7 then
            usageColor = colors.orange
        elseif detector.usage > 0.5 then
            usageColor = colors.yellow
        end

        self.monitor.setBackgroundColor(colors.gray)
        self.monitor.setCursorPos(barX, barY)
        self.monitor.write(string.rep(" ", barWidth))

        local filledWidth = math.floor(detector.usage * barWidth)
        self.monitor.setBackgroundColor(usageColor)
        self.monitor.setCursorPos(barX, barY)
        self.monitor.write(string.rep(" ", filledWidth))

        -- Stats
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.lightGray)

        self.monitor.setCursorPos(1, 7)
        self.monitor.write("Limit: " .. formatRate(detector.limit))

        self.monitor.setCursorPos(1, 8)
        self.monitor.write("Avg:   " .. formatRate(detector.average))

        self.monitor.setCursorPos(1, 9)
        self.monitor.write("Peak:  " .. formatRate(detector.peak))

        -- History graph
        if self.showHistory and #detector.history > 1 and self.height > 12 then
            self:renderGraph(detector.history, detector.peak, 11, self.height - 2)
        end

        -- Detector name at bottom
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(1, self.height)
        self.monitor.write(detector.name:sub(1, self.width - 1))
    end,

    renderMultiple = function(self, data)
        -- Title with total
        local title = "Flow: " .. formatRate(data.totalRate)
        MonitorHelpers.writeCentered(self.monitor, 1, title, colors.yellow)

        local y = 3
        local barWidth = self.width - 14

        for _, detector in ipairs(data.detectors) do
            if y >= self.height - 1 then break end

            -- Detector name
            self.monitor.setBackgroundColor(colors.black)
            self.monitor.setTextColor(colors.white)
            self.monitor.setCursorPos(1, y)
            self.monitor.write(("Det " .. detector.shortName):sub(1, 6))

            -- Usage bar
            local usageColor = colors.green
            if detector.usage > 0.9 then
                usageColor = colors.red
            elseif detector.usage > 0.7 then
                usageColor = colors.orange
            end

            self.monitor.setBackgroundColor(colors.gray)
            self.monitor.setCursorPos(8, y)
            self.monitor.write(string.rep(" ", barWidth))

            local filledWidth = math.floor(detector.usage * barWidth)
            self.monitor.setBackgroundColor(usageColor)
            self.monitor.setCursorPos(8, y)
            self.monitor.write(string.rep(" ", filledWidth))

            -- Rate value
            self.monitor.setBackgroundColor(colors.black)
            self.monitor.setTextColor(colors.lightGray)
            self.monitor.setCursorPos(8 + barWidth + 1, y)
            local shortRate = formatRate(detector.rate):gsub("FE/t", "")
            self.monitor.write(shortRate:sub(1, 6))

            y = y + 2
        end

        -- Total at bottom
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(1, self.height)
        self.monitor.write("Total: " .. formatRate(data.totalRate))
    end,

    renderGraph = function(self, history, maxVal, startY, endY)
        local graphHeight = endY - startY
        local graphWidth = math.min(#history, self.width - 2)

        if graphHeight < 2 or graphWidth < 2 then return end

        -- Draw graph
        local startX = math.floor((self.width - graphWidth) / 2) + 1

        for i = 1, graphWidth do
            local idx = #history - graphWidth + i
            if idx > 0 then
                local val = history[idx]
                local normalizedHeight = maxVal > 0 and (val / maxVal * graphHeight) or 0
                local barHeight = math.floor(normalizedHeight)

                for h = 0, graphHeight - 1 do
                    self.monitor.setCursorPos(startX + i - 1, endY - h)
                    if h < barHeight then
                        self.monitor.setBackgroundColor(colors.cyan)
                    else
                        self.monitor.setBackgroundColor(colors.black)
                    end
                    self.monitor.write(" ")
                end
            end
        end

        self.monitor.setBackgroundColor(colors.black)
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Energy Flow", colors.yellow)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "No energy detectors found", colors.gray)
    end
})
