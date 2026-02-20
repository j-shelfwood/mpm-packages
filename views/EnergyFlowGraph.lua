-- EnergyFlowGraph.lua
-- Dedicated dual-line graph for manual detector-mapped energy flow.

local BaseView = mpm('views/BaseView')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Text = mpm('utils/Text')
local Yield = mpm('utils/Yield')
local Peripherals = mpm('utils/Peripherals')
local EnergyInterface = mpm('peripherals/EnergyInterface')

local DETECTOR_REFRESH_SECONDS = 2
local STORAGE_REFRESH_SECONDS = 3
local FLOW_HISTORY_SIZE = 12
local RATE_HISTORY_SIZE = 6
local OUTLIER_FACTOR = 16
local IO_GRAPH_HISTORY_SIZE = 240

local function formatRate(fePerTick)
    local abs = math.abs(fePerTick)
    if abs >= 1e9 then
        return string.format("%.2f GFE/t", fePerTick / 1e9)
    elseif abs >= 1e6 then
        return string.format("%.2f MFE/t", fePerTick / 1e6)
    elseif abs > 1e4 then
        return string.format("%.1f kFE/t", fePerTick / 1e3)
    end
    return string.format("%.0f FE/t", fePerTick)
end

local function formatDuration(seconds)
    if not seconds or seconds < 0 then
        return nil
    end
    local total = math.floor(seconds + 0.5)
    local h = math.floor(total / 3600)
    local m = math.floor((total % 3600) / 60)
    local s = total % 60
    if h > 0 then
        return string.format("%dh %02dm", h, m)
    elseif m > 0 then
        return string.format("%dm %02ds", m, s)
    end
    return string.format("%ds", s)
end

local function toLuaPattern(wildcard)
    local pattern = wildcard or ""
    pattern = pattern:gsub("([%^%$%(%)%%%.%[%]%+%-])", "%%%1")
    pattern = pattern:gsub("%*", ".*")
    pattern = pattern:gsub("%?", ".")
    return "^" .. pattern .. "$"
end

local function matchesPattern(name, pattern)
    if not pattern or pattern == "" or pattern == "*" then
        return true
    end
    return name:match(toLuaPattern(pattern)) ~= nil
end

local function joulesToFE(value)
    if type(mekanismEnergyHelper) == "table" and type(mekanismEnergyHelper.joulesToFE) == "function" then
        local ok, converted = pcall(mekanismEnergyHelper.joulesToFE, value)
        if ok and type(converted) == "number" then
            return converted
        end
    end
    return value / 2.5
end

local function findDetectors()
    local detectors = {}
    local names = Peripherals.getNames()

    for idx, name in ipairs(names) do
        local p = Peripherals.wrap(name)
        local hasDetectorMethods = p and type(p.getTransferRate) == "function" and type(p.getTransferRateLimit) == "function"
        local hasDetectorType = Peripherals.hasType(name, "energy_detector")
            or Peripherals.typeMatches(Peripherals.getType(name), "energy_detector")

        if hasDetectorMethods or hasDetectorType then
            table.insert(detectors, {
                name = name,
                displayName = Peripherals.getDisplayName(name) or name,
                peripheral = p
            })
        end
        Yield.check(idx, 10)
    end

    table.sort(detectors, function(a, b) return (a.displayName or a.name) < (b.displayName or b.name) end)
    return detectors
end

local function getDetectorOptions()
    local detectors = findDetectors()
    local options = {}
    for _, d in ipairs(detectors) do
        table.insert(options, { value = d.name, label = d.displayName or d.name })
    end
    return options
end

local function normalizeDetectorSelection(value)
    local result = {}
    local seen = {}

    local function push(name)
        if type(name) ~= "string" or name == "" then return end
        if seen[name] then return end
        seen[name] = true
        table.insert(result, name)
    end

    if type(value) == "table" then
        for _, name in ipairs(value) do
            push(name)
        end
    elseif type(value) == "string" and value ~= "" then
        push(value)
    end

    return result
end

local function getStorageTotals(modFilter, nameFilter)
    local storages = EnergyInterface.findAll()
    local totals = {
        count = 0,
        storedFE = 0,
        capacityFE = 0
    }

    for idx, storage in ipairs(storages) do
        local classification = EnergyInterface.classify(storage.name, storage.primaryType)
        if (modFilter == "all" or classification.mod == modFilter) and matchesPattern(storage.name, nameFilter) then
            local status = EnergyInterface.getStatus(storage.peripheral)
            if status then
                totals.count = totals.count + 1
                if status.unit == "J" then
                    totals.storedFE = totals.storedFE + joulesToFE(status.stored)
                    totals.capacityFE = totals.capacityFE + joulesToFE(status.capacity)
                else
                    totals.storedFE = totals.storedFE + status.stored
                    totals.capacityFE = totals.capacityFE + status.capacity
                end
            end
        end
        Yield.check(idx, 10)
    end

    totals.percent = totals.capacityFE > 0 and (totals.storedFE / totals.capacityFE) or 0
    return totals
end

local function resolveSelectedDetectors(allDetectors, selectedNames)
    local byName = {}
    for _, detector in ipairs(allDetectors) do
        byName[detector.name] = detector
    end

    local resolved = {}
    for _, name in ipairs(selectedNames or {}) do
        if byName[name] then
            table.insert(resolved, byName[name])
        end
    end
    return resolved
end

local function unionDetectors(left, right)
    local combined = {}
    local seen = {}
    for _, detector in ipairs(left or {}) do
        if not seen[detector.name] then
            table.insert(combined, detector)
            seen[detector.name] = true
        end
    end
    for _, detector in ipairs(right or {}) do
        if not seen[detector.name] then
            table.insert(combined, detector)
            seen[detector.name] = true
        end
    end
    return combined
end

local function median(values)
    local n = #values
    if n == 0 then return 0 end
    local copy = {}
    for i, value in ipairs(values) do
        copy[i] = value
    end
    table.sort(copy)
    local mid = math.floor((n + 1) / 2)
    if n % 2 == 1 then
        return copy[mid]
    end
    return (copy[mid] + copy[mid + 1]) / 2
end

local function sanitizeRate(name, rawRate, limit, historyByName)
    local rate = rawRate
    if rate < 0 then
        rate = 0
    end
    if limit > 0 and rate > (limit * 1.05) then
        rate = limit
    end

    local history = historyByName[name] or {}
    local baseline = median(history)
    if #history >= 3 and baseline > 0 and rate > 5000 and rate > (baseline * OUTLIER_FACTOR) then
        rate = baseline
    end

    table.insert(history, rate)
    if #history > RATE_HISTORY_SIZE then
        table.remove(history, 1)
    end
    historyByName[name] = history

    return rate
end

local function sampleDetectorValues(detectors, rateHistoryByName)
    local sampled = {}
    for idx, detector in ipairs(detectors) do
        local p = detector.peripheral
        local rateOk, rate = pcall(p.getTransferRate)
        local limitOk, limit = pcall(p.getTransferRateLimit)
        local rawRate = (rateOk and type(rate) == "number") and rate or 0
        local currentLimit = (limitOk and type(limit) == "number") and limit or 0
        sampled[detector.name] = {
            rate = sanitizeRate(detector.name, rawRate, currentLimit, rateHistoryByName),
            limit = currentLimit
        }
        Yield.check(idx, 5)
    end
    return sampled
end

local function collectDetectorTotals(detectors, sampled)
    local totalRate = 0

    for _, det in ipairs(detectors) do
        local values = sampled[det.name] or { rate = 0, limit = 0 }
        totalRate = totalRate + values.rate
    end

    return totalRate
end

local function hasOverlap(left, right)
    local seen = {}
    for _, name in ipairs(left or {}) do
        seen[name] = true
    end
    for _, name in ipairs(right or {}) do
        if seen[name] then
            return true
        end
    end
    return false
end

local function classifyState(flowHistory, netRate)
    if #flowHistory == 0 then
        return "PASSIVE", colors.lightBlue
    end

    local sum = 0
    local absSum = 0
    local minValue = flowHistory[1]
    local maxValue = flowHistory[1]
    for _, value in ipairs(flowHistory) do
        sum = sum + value
        absSum = absSum + math.abs(value)
        if value < minValue then minValue = value end
        if value > maxValue then maxValue = value end
    end

    local avg = sum / #flowHistory
    local avgAbs = absSum / #flowHistory
    local spread = maxValue - minValue
    local passiveThreshold = math.max(25, avgAbs * 0.15)
    local spikeThreshold = math.max(250, avgAbs * 1.2)

    if spread >= spikeThreshold and #flowHistory >= 4 then
        return "SPIKING", colors.orange
    end
    if math.abs(netRate) <= passiveThreshold then
        return "PASSIVE", colors.lightBlue
    end
    if avg > passiveThreshold then
        return "CHARGING", colors.lime
    end
    if avg < -passiveThreshold then
        return "DISCHARGING", colors.red
    end
    return "STABLE", colors.cyan
end

local function drawHeaderBar(monitor, width, title, stateName, stateColor)
    monitor.setBackgroundColor(colors.gray)
    monitor.setTextColor(colors.black)
    monitor.setCursorPos(1, 1)
    monitor.write(string.rep(" ", width))

    monitor.setCursorPos(2, 1)
    monitor.write(Text.truncateMiddle(title, math.max(1, width - 2)))

    local state = stateName or "PASSIVE"
    local stateText = "[" .. state .. "]"
    stateText = Text.truncateMiddle(stateText, math.max(1, math.floor(width * 0.45)))
    local stateX = math.max(2, width - #stateText)
    monitor.setCursorPos(stateX, 1)
    monitor.setTextColor(stateColor or colors.lightBlue)
    monitor.write(stateText)

    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
end

local function drawMetricCard(monitor, x1, y1, x2, y2, title, value, accentBg, valueColor)
    MonitorHelpers.drawBox(monitor, x1, y1, x2, y2, colors.black, accentBg)
    local width = x2 - x1 + 1
    local titleText = Text.truncateMiddle(title, math.max(1, width - 2))
    local valueText = Text.truncateMiddle(value, math.max(1, width - 2))

    monitor.setTextColor(colors.lightGray)
    monitor.setCursorPos(x1 + 1, y1 + 1)
    monitor.write(titleText)

    monitor.setTextColor(valueColor or colors.white)
    monitor.setCursorPos(x1 + 1, y1 + 2)
    monitor.write(valueText)

    monitor.setTextColor(colors.white)
end

local function formatNet(netRate)
    if netRate > 0 then
        return "+" .. formatRate(netRate), colors.lime
    elseif netRate < 0 then
        return formatRate(netRate), colors.red
    end
    return formatRate(netRate), colors.white
end

local function drawCompact(self, data)
    drawHeaderBar(self.monitor, self.width, "ENERGY SYSTEM", data.stateName, data.stateColor)

    local inText = "IN  " .. formatRate(data.input.rate)
    local outText = "OUT " .. formatRate(data.output.rate)
    local netText, netColor = formatNet(data.netRate)

    self.monitor.setTextColor(colors.lime)
    self.monitor.setCursorPos(1, 3)
    self.monitor.write(Text.truncateMiddle(inText, self.width))

    self.monitor.setTextColor(colors.orange)
    self.monitor.setCursorPos(1, 4)
    self.monitor.write(Text.truncateMiddle(outText, self.width))

    self.monitor.setTextColor(netColor)
    self.monitor.setCursorPos(1, 5)
    self.monitor.write(Text.truncateMiddle("NET " .. netText, self.width))

    local barY = math.min(self.height - 2, 7)
    local storage = data.storage
    if storage.count > 0 and barY > 5 then
        MonitorHelpers.drawProgressBar(self.monitor, 1, barY, self.width, storage.percent * 100, colors.green, colors.gray, false)
        self.monitor.setTextColor(colors.lightGray)
        local bankLine = string.format("%s / %s", EnergyInterface.formatEnergy(storage.storedFE, "FE"), EnergyInterface.formatEnergy(storage.capacityFE, "FE"))
        self.monitor.setCursorPos(1, math.min(self.height - 1, barY + 1))
        self.monitor.write(Text.truncateMiddle(bankLine, self.width))
    end

    self.monitor.setTextColor(colors.gray)
    self.monitor.setCursorPos(1, self.height)
    self.monitor.write(Text.truncateMiddle("Input/Output history available on larger monitors", self.width))
end

local function drawDualHistoryGraph(monitor, x1, y1, x2, y2, inputHistory, outputHistory)
    local width = x2 - x1 + 1
    local height = y2 - y1 + 1
    if width < 8 or height < 4 then
        return
    end

    local points = math.min(width, #inputHistory, #outputHistory)
    if points < 2 then
        return
    end

    local maxValue = 1
    for i = #inputHistory - points + 1, #inputHistory do
        if inputHistory[i] and inputHistory[i] > maxValue then
            maxValue = inputHistory[i]
        end
        if outputHistory[i] and outputHistory[i] > maxValue then
            maxValue = outputHistory[i]
        end
    end

    for col = 1, points do
        local idx = #inputHistory - points + col
        local inValue = inputHistory[idx] or 0
        local outValue = outputHistory[idx] or 0

        local inY = y2 - math.floor((inValue / maxValue) * (height - 1))
        local outY = y2 - math.floor((outValue / maxValue) * (height - 1))

        local x = x1 + col - 1
        if inY == outY then
            monitor.setTextColor(colors.yellow)
            monitor.setCursorPos(x, inY)
            monitor.write("*")
        else
            monitor.setTextColor(colors.lime)
            monitor.setCursorPos(x, inY)
            monitor.write("I")

            monitor.setTextColor(colors.orange)
            monitor.setCursorPos(x, outY)
            monitor.write("O")
        end
    end

    monitor.setTextColor(colors.white)
end

return BaseView.custom({
    sleepTime = 1,

    configSchema = {
        {
            key = "input_detectors",
            type = "multiselect",
            label = "Input Detectors",
            options = getDetectorOptions,
            default = {},
            description = "Pick one or more IN lane detectors"
        },
        {
            key = "output_detectors",
            type = "multiselect",
            label = "Output Detectors",
            options = getDetectorOptions,
            default = {},
            description = "Pick one or more OUT lane detectors"
        },
        {
            key = "storage_mod_filter",
            type = "select",
            label = "Storage Mod",
            options = function()
                return EnergyInterface.getModFilterOptions()
            end,
            default = "all"
        },
        {
            key = "storage_name_filter",
            type = "text",
            label = "Storage Name Filter",
            default = "",
            description = "Optional wildcard filter for bank storages"
        }
    },

    mount = function()
        return #findDetectors() > 0 or EnergyInterface.exists()
    end,

    init = function(self, config)
        self.inputDetectorNames = normalizeDetectorSelection(config.input_detectors)
        self.outputDetectorNames = normalizeDetectorSelection(config.output_detectors)
        self.storageModFilter = config.storage_mod_filter or "all"
        self.storageNameFilter = config.storage_name_filter or ""
        self.flowHistory = {}
        self.inputRateHistory = {}
        self.outputRateHistory = {}
        self.rateHistoryByName = {}
        self.detectorCache = {}
        self.lastDetectorScanAt = nil
        self.storageCache = { count = 0, storedFE = 0, capacityFE = 0, percent = 0 }
        self.lastStoragePollAt = nil
    end,

    getData = function(self)
        local now = os.epoch("utc") / 1000
        if not self.lastDetectorScanAt or (now - self.lastDetectorScanAt) >= DETECTOR_REFRESH_SECONDS then
            self.detectorCache = findDetectors()
            self.lastDetectorScanAt = now

            -- Prune per-detector rate histories for detached/unknown detectors.
            local active = {}
            for _, detector in ipairs(self.detectorCache) do
                active[detector.name] = true
            end
            for name in pairs(self.rateHistoryByName) do
                if not active[name] then
                    self.rateHistoryByName[name] = nil
                end
            end
        end

        local allDetectors = self.detectorCache
        local inputDetectors = resolveSelectedDetectors(allDetectors, self.inputDetectorNames)
        local outputDetectors = resolveSelectedDetectors(allDetectors, self.outputDetectorNames)
        local polledDetectors = unionDetectors(inputDetectors, outputDetectors)
        local sampled = sampleDetectorValues(polledDetectors, self.rateHistoryByName)

        local inRate = collectDetectorTotals(inputDetectors, sampled)
        local outRate = collectDetectorTotals(outputDetectors, sampled)
        local netRate = inRate - outRate
        MonitorHelpers.recordHistory(self.inputRateHistory, inRate, IO_GRAPH_HISTORY_SIZE)
        MonitorHelpers.recordHistory(self.outputRateHistory, outRate, IO_GRAPH_HISTORY_SIZE)

        table.insert(self.flowHistory, netRate)
        if #self.flowHistory > FLOW_HISTORY_SIZE then
            table.remove(self.flowHistory, 1)
        end

        local storage = self.storageCache
        if not self.lastStoragePollAt or (now - self.lastStoragePollAt) >= STORAGE_REFRESH_SECONDS then
            storage = getStorageTotals(self.storageModFilter, self.storageNameFilter)
            self.storageCache = storage
            self.lastStoragePollAt = now
        end
        local stateName, stateColor = classifyState(self.flowHistory, netRate)

        local etaToFull = nil
        local etaToEmpty = nil
        if storage.capacityFE > 0 and netRate > 0 then
            etaToFull = (storage.capacityFE - storage.storedFE) / (netRate * 20)
        elseif storage.storedFE > 0 and netRate < 0 then
            etaToEmpty = storage.storedFE / (math.abs(netRate) * 20)
        end

        return {
            detectorCount = #allDetectors,
            input = { rate = inRate, count = #inputDetectors },
            output = { rate = outRate, count = #outputDetectors },
            netRate = netRate,
            storage = storage,
            etaToFull = etaToFull,
            etaToEmpty = etaToEmpty,
            stateName = stateName,
            stateColor = stateColor,
            overlap = hasOverlap(self.inputDetectorNames, self.outputDetectorNames),
            inputHistory = self.inputRateHistory,
            outputHistory = self.outputRateHistory
        }
    end,

    render = function(self, data)
        if self.width < 30 or self.height < 12 then
            drawCompact(self, data)
            return
        end

        local monitor = self.monitor
        local width = self.width
        local height = self.height

        drawHeaderBar(monitor, width, "ENERGY FLOW GRAPH", data.stateName, data.stateColor)

        local summaryY = 3
        monitor.setTextColor(colors.lime)
        monitor.setCursorPos(2, summaryY)
        monitor.write(Text.truncateMiddle("IN  " .. formatRate(data.input.rate), math.max(1, width - 2)))

        monitor.setTextColor(colors.orange)
        monitor.setCursorPos(2, summaryY + 1)
        monitor.write(Text.truncateMiddle("OUT " .. formatRate(data.output.rate), math.max(1, width - 2)))

        local netText, netColor = formatNet(data.netRate)
        monitor.setTextColor(netColor)
        monitor.setCursorPos(2, summaryY + 2)
        monitor.write(Text.truncateMiddle("NET " .. netText, math.max(1, width - 2)))

        local graphTop = summaryY + 4
        local graphBottom = height - 1
        if graphTop <= graphBottom then
            monitor.setTextColor(colors.gray)
            monitor.setCursorPos(2, graphTop)
            monitor.write(Text.truncateMiddle("History  I=IN O=OUT *=BOTH", math.max(1, width - 2)))
            drawDualHistoryGraph(monitor, 2, graphTop + 1, width - 1, graphBottom, data.inputHistory, data.outputHistory)
        end

        if data.overlap then
            monitor.setTextColor(colors.red)
            monitor.setCursorPos(1, height)
            monitor.write(Text.truncateMiddle("WARN: IN and OUT detector overlap", width))
        end
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Energy Flow Graph", colors.yellow)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "No detectors/storage found", colors.gray)
    end
})
