-- Clock.lua
-- Displays Minecraft time, weather, moon phase, and biome
-- Uses environment_detector if available, falls back to os.time()

local BaseView = mpm('views/BaseView')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')
local Peripherals = mpm('utils/Peripherals')
local Core = mpm('ui/Core')

-- Moon phase names
local MOON_PHASES = {
    [0] = "Full Moon",
    [1] = "Waning Gibbous",
    [2] = "Third Quarter",
    [3] = "Waning Crescent",
    [4] = "New Moon",
    [5] = "Waxing Crescent",
    [6] = "First Quarter",
    [7] = "Waxing Gibbous"
}

local function formatTime(time, use24h)
    local hours = math.floor(time)
    local minutes = math.floor((time - hours) * 60)

    if use24h then
        return string.format("%02d:%02d", hours, minutes)
    else
        local period = "AM"
        if hours >= 12 then
            period = "PM"
            if hours > 12 then hours = hours - 12 end
        end
        if hours == 0 then hours = 12 end
        return string.format("%d:%02d %s", hours, minutes, period)
    end
end

local function getTimeOfDay(time)
    if time >= 6 and time < 12 then
        return "Morning", colors.yellow
    elseif time >= 12 and time < 17 then
        return "Afternoon", colors.orange
    elseif time >= 17 and time < 20 then
        return "Evening", colors.orange
    else
        return "Night", colors.blue
    end
end

local function callFirst(target, methods, ...)
    if not target then return nil end
    for _, methodName in ipairs(methods) do
        local fn = target[methodName]
        if type(fn) == "function" then
            local ok, a, b = pcall(fn, ...)
            if ok then
                return a, b
            end
        end
    end
    return nil
end

local function normalizeName(value, fallback)
    if type(value) == "table" then
        value = value.name or value.id or value.biome or value.dimension
    end
    if type(value) ~= "string" or value == "" then
        return fallback
    end
    return Text.prettifyName(value)
end

local function toClockHours(ticks)
    if type(ticks) ~= "number" then return nil end
    return ((ticks / 1000) + 6) % 24
end

local function buildRadarLines(width, radius, entities)
    local mapWidth = math.max(9, math.min(width - 2, 19))
    if mapWidth % 2 == 0 then
        mapWidth = mapWidth - 1
    end
    local mapHeight = 5
    local centerX = math.floor((mapWidth + 1) / 2)
    local centerY = math.floor((mapHeight + 1) / 2)
    local lines = {}

    for y = 1, mapHeight do
        lines[y] = string.rep(".", mapWidth)
    end

    local function writeChar(line, x, ch)
        if x < 1 or x > #line then return line end
        return line:sub(1, x - 1) .. ch .. line:sub(x + 1)
    end

    lines[centerY] = writeChar(lines[centerY], centerX, "@")

    for _, e in ipairs(entities or {}) do
        if type(e) == "table" and type(e.x) == "number" and type(e.z) == "number" then
            local px = math.floor(((e.x / radius) * ((mapWidth - 1) / 2)) + centerX + 0.5)
            local py = math.floor(((e.z / radius) * ((mapHeight - 1) / 2)) + centerY + 0.5)
            px = math.max(1, math.min(mapWidth, px))
            py = math.max(1, math.min(mapHeight, py))
            lines[py] = writeChar(lines[py], px, "*")
        end
    end

    return lines
end

return BaseView.custom({
    sleepTime = 1,

    configSchema = {
        {
            key = "timeFormat",
            type = "select",
            label = "Time Format",
            options = {
                { value = "12h", label = "12-hour (AM/PM)" },
                { value = "24h", label = "24-hour" }
            },
            default = "12h"
        },
        {
            key = "showBiome",
            type = "select",
            label = "Show Biome",
            options = {
                { value = true, label = "Yes" },
                { value = false, label = "No" }
            },
            default = true
        },
        {
            key = "showRadar",
            type = "select",
            label = "Show Radar",
            options = {
                { value = true, label = "Yes" },
                { value = false, label = "No" }
            },
            default = false
        },
        {
            key = "radarRadius",
            type = "number",
            label = "Radar Radius",
            default = 8,
            min = 4,
            max = 32,
            presets = {8, 12, 16}
        },
        {
            key = "radarInterval",
            type = "number",
            label = "Radar Interval (s)",
            default = 5,
            min = 2,
            max = 30,
            presets = {3, 5, 10}
        }
    },

    mount = function()
        return true  -- Always available, falls back to os.time()
    end,

    init = function(self, config)
        self.detector = Peripherals.find("environment_detector")
        self.use24h = config.timeFormat == "24h"
        self.showBiome = config.showBiome ~= false
        self.showRadar = config.showRadar == true
        self.radarRadius = tonumber(config.radarRadius) or 8
        self.radarInterval = tonumber(config.radarInterval) or 5
        self._radarAt = 0
        self._radarEntities = {}
        self._radarError = nil
        self._radarCost = nil
    end,

    getData = function(self)
        if not self.detector then
            self.detector = Peripherals.find("environment_detector")
        end

        local time = 12
        local weather = "clear"
        local isRaining = false
        local isThundering = false
        local moonPhase = 0
        local biome = "Unknown"
        local dimension = "Overworld"
        local radarEntities = self._radarEntities or {}
        local radarError = self._radarError
        local radarCost = self._radarCost
        local radarSupported = false

        if self.detector then
            -- Time
            local t = callFirst(self.detector, {"getTime"})
            local h = toClockHours(t)
            if h then
                time = h
            end

            -- Weather
            local rain = callFirst(self.detector, {"isRaining"})
            if type(rain) == "boolean" then isRaining = rain end
            local thunder = callFirst(self.detector, {"isThunder", "isThundering"})
            if type(thunder) == "boolean" then isThundering = thunder end

            if isThundering then
                weather = "thunder"
            elseif isRaining then
                weather = "rain"
            end

            -- Moon
            local moon = callFirst(self.detector, {"getMoonId", "getMoonPhase"})
            if type(moon) == "number" then moonPhase = moon end

            -- Biome
            biome = normalizeName(callFirst(self.detector, {"getBiome", "getBiomeName"}), biome)

            -- Dimension
            dimension = normalizeName(callFirst(self.detector, {"getDimension", "getDimensionName"}), dimension)

            -- Optional entity radar (rate-limited due scan fuel/time cost)
            local scanFn = self.detector.scanEntities
            if self.showRadar and type(scanFn) == "function" then
                radarSupported = true
                local now = os.epoch("utc")
                if now - self._radarAt >= (self.radarInterval * 1000) then
                    self._radarAt = now
                    local cost, costErr = callFirst(self.detector, {"scanCost"}, self.radarRadius)
                    if type(cost) == "number" then
                        self._radarCost = cost
                    elseif costErr then
                        self._radarCost = nil
                    end

                    local ok, entities, err = pcall(scanFn, self.radarRadius)
                    if ok and type(entities) == "table" then
                        self._radarEntities = entities
                        self._radarError = nil
                    else
                        self._radarError = tostring(err or entities or "scan_failed")
                    end
                end
                radarEntities = self._radarEntities or {}
                radarError = self._radarError
                radarCost = self._radarCost
            end

            Yield.yield()
        else
            time = os.time()
        end

        return {
            time = time,
            weather = weather,
            moonPhase = moonPhase,
            biome = biome,
            dimension = dimension,
            hasDetector = self.detector ~= nil,
            radarEntities = radarEntities,
            radarError = radarError,
            radarCost = radarCost,
            radarSupported = radarSupported
        }
    end,

    render = function(self, data)
        local timeStr = formatTime(data.time, self.use24h)
        local timeOfDay, todColor = getTimeOfDay(data.time)

        -- Row 1: Title
        MonitorHelpers.writeCentered(self.monitor, 1, "CLOCK", colors.lightBlue)

        -- Row 3: Large time display
        MonitorHelpers.writeCentered(self.monitor, 3, timeStr, colors.white)

        -- Row 4: Time of day
        MonitorHelpers.writeCentered(self.monitor, 4, timeOfDay, todColor)

        local row = 6

        -- Weather
        if data.weather == "thunder" then
            Core.drawLabelValue(self.monitor, row, "Weather:", "Thunder", {
                labelColor = colors.white,
                valueColor = colors.yellow
            })
        elseif data.weather == "rain" then
            Core.drawLabelValue(self.monitor, row, "Weather:", "Rain", {
                labelColor = colors.white,
                valueColor = colors.lightBlue
            })
        else
            Core.drawLabelValue(self.monitor, row, "Weather:", "Clear", {
                labelColor = colors.white,
                valueColor = colors.green
            })
        end
        row = row + 1

        -- Moon (only at night)
        if data.time < 6 or data.time >= 20 then
            self.monitor.setTextColor(colors.white)
            self.monitor.setCursorPos(1, row)
            self.monitor.write("Moon: ")
            self.monitor.setTextColor(colors.lightGray)
            local moonName = MOON_PHASES[data.moonPhase] or "Unknown"
            self.monitor.write(Text.truncateMiddle(moonName, self.width - 6))
            row = row + 1
        end

        -- Biome (configurable)
        if self.showBiome and row < self.height - 1 then
            self.monitor.setTextColor(colors.white)
            self.monitor.setCursorPos(1, row)
            self.monitor.write("Biome: ")
            self.monitor.setTextColor(colors.lime)
            self.monitor.write(Text.truncateMiddle(data.biome, self.width - 7))
            row = row + 1
        end

        -- Dimension
        if row < self.height - 1 then
            self.monitor.setTextColor(colors.white)
            self.monitor.setCursorPos(1, row)
            self.monitor.write("Dim: ")
            self.monitor.setTextColor(colors.purple)
            self.monitor.write(Text.truncateMiddle(data.dimension, self.width - 5))
            row = row + 1
        end

        -- Optional mini radar map (entities around detector)
        if self.showRadar and data.hasDetector and data.radarSupported and row <= self.height - 2 then
            self.monitor.setTextColor(colors.white)
            self.monitor.setCursorPos(1, row)
            local count = #data.radarEntities
            local costText = data.radarCost and (" c:" .. tostring(data.radarCost)) or ""
            self.monitor.write(Text.truncateMiddle("Radar r=" .. self.radarRadius .. " n=" .. count .. costText, self.width))
            row = row + 1

            if row <= self.height - 2 then
                local lines = buildRadarLines(self.width, self.radarRadius, data.radarEntities)
                for i = 1, #lines do
                    if row > self.height - 1 then break end
                    self.monitor.setCursorPos(1, row)
                    self.monitor.setTextColor(colors.gray)
                    self.monitor.write(Text.truncateMiddle(lines[i], self.width))
                    row = row + 1
                end
            end

            if data.radarError and row <= self.height - 1 then
                self.monitor.setCursorPos(1, row)
                self.monitor.setTextColor(colors.orange)
                self.monitor.write(Text.truncateMiddle("Radar: " .. data.radarError, self.width))
            end
        end

        -- Bottom: Detector status
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(1, self.height)
        if data.hasDetector then
            self.monitor.write("Env Detector: OK")
        else
            self.monitor.write("CC time (no detector)")
        end

        self.monitor.setTextColor(colors.white)
    end
})
