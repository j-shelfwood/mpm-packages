-- EnergySystem.lua
-- Manual detector-mapped energy monitor:
-- source -> [IN detectors] -> storage bank -> [OUT detectors] -> load

local BaseView = mpm('views/BaseView')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Text = mpm('utils/Text')
local Yield = mpm('utils/Yield')
local Peripherals = mpm('utils/Peripherals')
local EnergyInterface = mpm('peripherals/EnergyInterface')

local DETECTOR_REFRESH_SECONDS = 2
local FLOW_HISTORY_SIZE = 12
local RATE_HISTORY_SIZE = 6
local OUTLIER_FACTOR = 16

local function formatRate(fePerTick)
    if fePerTick >= 1e9 then
        return string.format("%.2f GFE/t", fePerTick / 1e9)
    elseif fePerTick >= 1e6 then
        return string.format("%.2f MFE/t", fePerTick / 1e6)
    elseif fePerTick >= 1e3 then
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
        if Peripherals.hasType(name, "energy_detector") or Peripherals.getType(name) == "energy_detector" then
            local p = Peripherals.wrap(name)
            if p and p.getTransferRate and p.getTransferRateLimit then
                table.insert(detectors, { name = name, peripheral = p })
            end
        end
        Yield.check(idx, 10)
    end

    table.sort(detectors, function(a, b) return a.name < b.name end)
    return detectors
end

local function getDetectorOptions()
    local detectors = findDetectors()
    local options = {}
    for _, d in ipairs(detectors) do
        table.insert(options, { value = d.name, label = d.name })
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
    local totalLimit = 0
    local entries = {}

    for _, det in ipairs(detectors) do
        local values = sampled[det.name] or { rate = 0, limit = 0 }
        totalRate = totalRate + values.rate
        totalLimit = totalLimit + values.limit
        table.insert(entries, {
            name = det.name,
            rate = values.rate,
            limit = values.limit
        })
    end

    return totalRate, totalLimit, entries
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

return BaseView.custom({
    sleepTime = 0.5,

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
        },
        {
            key = "show_breakdown",
            type = "select",
            label = "Detector Breakdown",
            options = {
                { value = "yes", label = "Yes" },
                { value = "no", label = "No" }
            },
            default = "yes"
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
        self.showBreakdown = config.show_breakdown ~= "no"
        self.flowHistory = {}
        self.rateHistoryByName = {}
        self.detectorCache = {}
        self.lastDetectorScanAt = nil
    end,

    getData = function(self)
        local now = os.epoch("utc") / 1000
        if not self.lastDetectorScanAt or (now - self.lastDetectorScanAt) >= DETECTOR_REFRESH_SECONDS then
            self.detectorCache = findDetectors()
            self.lastDetectorScanAt = now
        end

        local allDetectors = self.detectorCache
        local inputDetectors = resolveSelectedDetectors(allDetectors, self.inputDetectorNames)
        local outputDetectors = resolveSelectedDetectors(allDetectors, self.outputDetectorNames)
        local polledDetectors = unionDetectors(inputDetectors, outputDetectors)
        local sampled = sampleDetectorValues(polledDetectors, self.rateHistoryByName)

        local inRate, inLimit, inEntries = collectDetectorTotals(inputDetectors, sampled)
        local outRate, outLimit, outEntries = collectDetectorTotals(outputDetectors, sampled)
        local netRate = inRate - outRate

        table.insert(self.flowHistory, netRate)
        if #self.flowHistory > FLOW_HISTORY_SIZE then
            table.remove(self.flowHistory, 1)
        end

        local storage = getStorageTotals(self.storageModFilter, self.storageNameFilter)
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
            input = { rate = inRate, limit = inLimit, entries = inEntries, count = #inputDetectors },
            output = { rate = outRate, limit = outLimit, entries = outEntries, count = #outputDetectors },
            netRate = netRate,
            storage = storage,
            etaToFull = etaToFull,
            etaToEmpty = etaToEmpty,
            stateName = stateName,
            stateColor = stateColor,
            overlap = hasOverlap(self.inputDetectorNames, self.outputDetectorNames)
        }
    end,

    render = function(self, data)
        local y = 1
        MonitorHelpers.writeCentered(self.monitor, y, "Energy System", colors.yellow)
        y = y + 2

        self.monitor.setTextColor(colors.lime)
        MonitorHelpers.writeCentered(self.monitor, y, "INPUT")
        y = y + 1
        MonitorHelpers.writeCentered(self.monitor, y, formatRate(data.input.rate), colors.lime)
        y = y + 1

        self.monitor.setTextColor(colors.orange)
        MonitorHelpers.writeCentered(self.monitor, y, "OUTPUT")
        y = y + 1
        MonitorHelpers.writeCentered(self.monitor, y, formatRate(data.output.rate), colors.orange)
        y = y + 1

        local netColor = colors.white
        local netPrefix = ""
        if data.netRate > 0 then
            netColor = colors.lime
            netPrefix = "+"
        elseif data.netRate < 0 then
            netColor = colors.red
        end
        MonitorHelpers.writeCentered(self.monitor, y, "NET " .. netPrefix .. formatRate(data.netRate), netColor)
        y = y + 1

        MonitorHelpers.writeCentered(self.monitor, y, "State: " .. (data.stateName or "PASSIVE"), data.stateColor or colors.lightBlue)
        y = y + 1

        local storage = data.storage
        if storage.count > 0 and y < self.height - 2 then
            local barWidth = math.max(1, self.width - 2)
            MonitorHelpers.drawProgressBar(self.monitor, 1, y, barWidth, storage.percent * 100, colors.green, colors.gray, false)
            y = y + 1

            self.monitor.setTextColor(colors.lightGray)
            self.monitor.setCursorPos(1, y)
            self.monitor.write(Text.truncateMiddle(
                string.format("Bank: %s / %s", EnergyInterface.formatEnergy(storage.storedFE, "FE"), EnergyInterface.formatEnergy(storage.capacityFE, "FE")),
                self.width
            ))
            y = y + 1

            self.monitor.setTextColor(colors.gray)
            local eta = data.etaToFull and ("Full in " .. formatDuration(data.etaToFull))
                or (data.etaToEmpty and ("Empty in " .. formatDuration(data.etaToEmpty)))
                or "Stable"
            self.monitor.setCursorPos(1, y)
            self.monitor.write(Text.truncateMiddle(eta, self.width))
            y = y + 1
        elseif y < self.height - 1 then
            self.monitor.setTextColor(colors.orange)
            self.monitor.setCursorPos(1, y)
            self.monitor.write("No energy storages matched")
            y = y + 1
        end

        if data.overlap and y < self.height - 1 then
            self.monitor.setTextColor(colors.red)
            self.monitor.setCursorPos(1, y)
            self.monitor.write(Text.truncateMiddle("WARN: IN and OUT share detector(s)", self.width))
            y = y + 1
        end

        if self.showBreakdown and y < self.height - 1 then
            self.monitor.setTextColor(colors.gray)
            self.monitor.setCursorPos(1, y)
            self.monitor.write("Detectors:")
            y = y + 1

            for _, entry in ipairs(data.input.entries) do
                if y > self.height - 1 then break end
                self.monitor.setTextColor(colors.lime)
                self.monitor.setCursorPos(1, y)
                self.monitor.write(Text.truncateMiddle("I " .. entry.name .. " " .. formatRate(entry.rate), self.width))
                y = y + 1
            end
            for _, entry in ipairs(data.output.entries) do
                if y > self.height - 1 then break end
                self.monitor.setTextColor(colors.orange)
                self.monitor.setCursorPos(1, y)
                self.monitor.write(Text.truncateMiddle("O " .. entry.name .. " " .. formatRate(entry.rate), self.width))
                y = y + 1
            end
        end

        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(1, self.height)
        self.monitor.write(Text.truncateMiddle(
            string.format("IN:%d OUT:%d | %d storages", data.input.count, data.output.count, data.storage.count),
            self.width
        ))
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Energy System", colors.yellow)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "No detectors/storage found", colors.gray)
    end
})
