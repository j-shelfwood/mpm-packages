-- EnergySystem.lua
-- Battery-centric energy monitor for detector-first topologies:
-- source -> input detector -> storage bank -> output detector -> load

local BaseView = mpm('views/BaseView')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Text = mpm('utils/Text')
local Yield = mpm('utils/Yield')
local Peripherals = mpm('utils/Peripherals')
local EnergyInterface = mpm('peripherals/EnergyInterface')

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

local function feToJoules(value)
    if type(mekanismEnergyHelper) == "table" and type(mekanismEnergyHelper.feToJoules) == "function" then
        local ok, converted = pcall(mekanismEnergyHelper.feToJoules, value)
        if ok and type(converted) == "number" then
            return converted
        end
    end
    return value * 2.5
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
    local options = {
        { value = "auto_input", label = "Auto Input (first)" },
        { value = "auto_output", label = "Auto Output (second)" },
        { value = "all", label = "All Detectors (sum)" }
    }
    for _, d in ipairs(detectors) do
        table.insert(options, { value = d.name, label = d.name })
    end
    return options
end

local function selectDetectors(detectors, selector)
    if selector == "all" then
        return detectors
    end

    if selector == "auto_input" then
        return detectors[1] and {detectors[1]} or {}
    end

    if selector == "auto_output" then
        if #detectors >= 2 then
            return {detectors[2]}
        elseif #detectors == 1 then
            return {detectors[1]}
        end
        return {}
    end

    for _, d in ipairs(detectors) do
        if d.name == selector then
            return {d}
        end
    end
    return {}
end

local function collectDetectorTotals(detectors)
    local totalRate = 0
    local totalLimit = 0
    local entries = {}

    for idx, det in ipairs(detectors) do
        local p = det.peripheral
        local rateOk, rate = pcall(p.getTransferRate)
        local limitOk, limit = pcall(p.getTransferRateLimit)
        local currentRate = (rateOk and type(rate) == "number") and rate or 0
        local currentLimit = (limitOk and type(limit) == "number") and limit or 0

        totalRate = totalRate + currentRate
        totalLimit = totalLimit + currentLimit
        table.insert(entries, {
            name = det.name,
            rate = currentRate,
            limit = currentLimit
        })
        Yield.check(idx, 5)
    end

    return totalRate, totalLimit, entries
end

local function getResolvedRoleName(selector, detectors, roleLabel)
    if #detectors == 1 then
        return detectors[1].name
    end
    if selector == "auto_input" then
        return "AUTO(first)"
    end
    if selector == "auto_output" then
        return "AUTO(second)"
    end
    if selector == "all" then
        return "ALL"
    end
    return roleLabel .. ":none"
end

local function getConfidenceState(storagePercent, netRate)
    if storagePercent >= 0.95 and netRate >= 0 then
        return "CURTAILED", "LOW", colors.orange
    end
    if storagePercent <= 0.05 and netRate <= 0 then
        return "SUPPLY-LIMITED", "LOW", colors.red
    end
    if storagePercent >= 0.15 and storagePercent <= 0.85 then
        return "STEADY", "HIGH", colors.lime
    end
    return "TRANSIENT", "MED", colors.yellow
end

local function getStorageTotals(modFilter, nameFilter)
    local storages = EnergyInterface.findAll()
    local totals = {
        count = 0,
        storedJ = 0,
        capacityJ = 0,
        storedFE = 0,
        capacityFE = 0,
        hasJ = false
    }

    for idx, storage in ipairs(storages) do
        local classification = EnergyInterface.classify(storage.name, storage.primaryType)
        if (modFilter == "all" or classification.mod == modFilter) and matchesPattern(storage.name, nameFilter) then
            local status = EnergyInterface.getStatus(storage.peripheral)
            if status then
                totals.count = totals.count + 1
                if status.unit == "J" then
                    totals.hasJ = true
                    totals.storedJ = totals.storedJ + status.stored
                    totals.capacityJ = totals.capacityJ + status.capacity
                    totals.storedFE = totals.storedFE + joulesToFE(status.stored)
                    totals.capacityFE = totals.capacityFE + joulesToFE(status.capacity)
                else
                    totals.storedFE = totals.storedFE + status.stored
                    totals.capacityFE = totals.capacityFE + status.capacity
                    totals.storedJ = totals.storedJ + feToJoules(status.stored)
                    totals.capacityJ = totals.capacityJ + feToJoules(status.capacity)
                end
            end
        end
        Yield.check(idx, 10)
    end

    totals.percent = totals.capacityFE > 0 and (totals.storedFE / totals.capacityFE) or 0
    return totals
end

return BaseView.custom({
    sleepTime = 0.5,

    configSchema = {
        {
            key = "input_detector",
            type = "select",
            label = "Input Lane Detector",
            options = getDetectorOptions,
            default = "auto_input",
            description = "Detector between source entangloporter and battery bank"
        },
        {
            key = "output_detector",
            type = "select",
            label = "Output Lane Detector",
            options = getDetectorOptions,
            default = "auto_output",
            description = "Detector between battery bank and load entangloporter"
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
        self.inputDetector = config.input_detector or "auto_input"
        self.outputDetector = config.output_detector or "auto_output"
        self.storageModFilter = config.storage_mod_filter or "all"
        self.storageNameFilter = config.storage_name_filter or ""
        self.showBreakdown = config.show_breakdown ~= "no"
    end,

    getData = function(self)
        local allDetectors = findDetectors()
        local inputDetectors = selectDetectors(allDetectors, self.inputDetector)
        local outputDetectors = selectDetectors(allDetectors, self.outputDetector)

        local inRate, inLimit, inEntries = collectDetectorTotals(inputDetectors)
        local outRate, outLimit, outEntries = collectDetectorTotals(outputDetectors)
        local netRate = inRate - outRate
        local inputRoleName = getResolvedRoleName(self.inputDetector, inputDetectors, "IN")
        local outputRoleName = getResolvedRoleName(self.outputDetector, outputDetectors, "OUT")
        local sameDetectorMapped = (#inputDetectors == 1 and #outputDetectors == 1 and inputDetectors[1].name == outputDetectors[1].name)

        local storage = getStorageTotals(self.storageModFilter, self.storageNameFilter)
        local stateName, stateConfidence, stateColor = getConfidenceState(storage.percent or 0, netRate)

        local etaToFull = nil
        local etaToEmpty = nil
        if storage.capacityFE > 0 and netRate > 0 then
            etaToFull = (storage.capacityFE - storage.storedFE) / (netRate * 20)
        elseif storage.storedFE > 0 and netRate < 0 then
            etaToEmpty = storage.storedFE / (math.abs(netRate) * 20)
        end

        return {
            detectorCount = #allDetectors,
            input = { rate = inRate, limit = inLimit, entries = inEntries },
            output = { rate = outRate, limit = outLimit, entries = outEntries },
            netRate = netRate,
            storage = storage,
            etaToFull = etaToFull,
            etaToEmpty = etaToEmpty,
            stateName = stateName,
            stateConfidence = stateConfidence,
            stateColor = stateColor,
            inputRoleName = inputRoleName,
            outputRoleName = outputRoleName,
            sameDetectorMapped = sameDetectorMapped
        }
    end,

    render = function(self, data)
        local y = 1

        MonitorHelpers.writeCentered(self.monitor, y, "Energy System", colors.yellow)
        y = y + 2

        self.monitor.setTextColor(colors.lime)
        self.monitor.setCursorPos(1, y)
        self.monitor.write("IN : " .. Text.truncateMiddle(formatRate(data.input.rate), math.max(1, self.width - 6)))
        y = y + 1

        self.monitor.setTextColor(colors.orange)
        self.monitor.setCursorPos(1, y)
        self.monitor.write("OUT: " .. Text.truncateMiddle(formatRate(data.output.rate), math.max(1, self.width - 6)))
        y = y + 1

        local netColor = colors.white
        local netPrefix = ""
        if data.netRate > 0 then
            netColor = colors.lime
            netPrefix = "+"
        elseif data.netRate < 0 then
            netColor = colors.red
        end
        self.monitor.setTextColor(netColor)
        self.monitor.setCursorPos(1, y)
        self.monitor.write("NET: " .. netPrefix .. formatRate(data.netRate))
        y = y + 1

        self.monitor.setTextColor(data.stateColor or colors.yellow)
        self.monitor.setCursorPos(1, y)
        self.monitor.write(Text.truncateMiddle(
            string.format("State: %s (%s)", data.stateName or "TRANSIENT", data.stateConfidence or "MED"),
            self.width
        ))
        y = y + 2

        local storage = data.storage
        if storage.count > 0 then
            local barWidth = math.max(1, self.width - 2)
            MonitorHelpers.drawProgressBar(self.monitor, 1, y, barWidth, storage.percent * 100, colors.green, colors.gray, false)
            y = y + 1

            local stored, capacity, unit
            if storage.hasJ then
                stored = storage.storedJ
                capacity = storage.capacityJ
                unit = "J"
            else
                stored = storage.storedFE
                capacity = storage.capacityFE
                unit = "FE"
            end

            self.monitor.setTextColor(colors.lightGray)
            self.monitor.setCursorPos(1, y)
            self.monitor.write(Text.truncateMiddle(
                string.format("Bank: %s / %s", EnergyInterface.formatEnergy(stored, unit), EnergyInterface.formatEnergy(capacity, unit)),
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
        else
            self.monitor.setTextColor(colors.orange)
            self.monitor.setCursorPos(1, y)
            self.monitor.write("No energy storages matched")
            y = y + 1
        end

        if y < self.height - 1 then
            self.monitor.setTextColor(colors.gray)
            self.monitor.setCursorPos(1, y)
            self.monitor.write(Text.truncateMiddle("IN=" .. data.inputRoleName .. " OUT=" .. data.outputRoleName, self.width))
            y = y + 1
        end

        if data.sameDetectorMapped and y < self.height - 1 then
            self.monitor.setTextColor(colors.red)
            self.monitor.setCursorPos(1, y)
            self.monitor.write(Text.truncateMiddle("WARN: IN and OUT use same detector", self.width))
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
            string.format("%d detectors | %d storages", data.detectorCount, data.storage.count),
            self.width
        ))
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Energy System", colors.yellow)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "No detectors/storage found", colors.gray)
    end
})
