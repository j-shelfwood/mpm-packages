-- Clock.lua
-- Displays Minecraft time, weather, moon phase, and biome
-- Uses environment_detector if available, falls back to os.time()

local BaseView = mpm('views/BaseView')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

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

local function formatTime(time)
    local hours = math.floor(time)
    local minutes = math.floor((time - hours) * 60)
    local period = "AM"

    if hours >= 12 then
        period = "PM"
        if hours > 12 then hours = hours - 12 end
    end
    if hours == 0 then hours = 12 end

    return string.format("%d:%02d %s", hours, minutes, period)
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

return BaseView.custom({
    sleepTime = 1,

    configSchema = nil,

    mount = function()
        return true  -- Always available, falls back to os.time()
    end,

    init = function(self, config)
        self.detector = peripheral.find("environment_detector")
    end,

    getData = function(self)
        local time = 12
        local weather = "clear"
        local isRaining = false
        local isThundering = false
        local moonPhase = 0
        local biome = "Unknown"
        local dimension = "Overworld"

        if self.detector then
            -- Time
            local ok, t = pcall(self.detector.getTime)
            if ok and t then
                time = t / 1000
                if time > 24 then time = time - 24 end
            end

            -- Weather
            local rainOk, rain = pcall(self.detector.isRaining)
            if rainOk then isRaining = rain end

            local thunderOk, thunder = pcall(self.detector.isThundering)
            if thunderOk then isThundering = thunder end

            if isThundering then
                weather = "thunder"
            elseif isRaining then
                weather = "rain"
            end

            -- Moon
            local moonOk, moon = pcall(self.detector.getMoonPhase)
            if moonOk and moon then moonPhase = moon end

            -- Biome
            local biomeOk, b = pcall(self.detector.getBiome)
            if biomeOk and b then
                biome = Text.prettifyName(b)
            end

            -- Dimension
            local dimOk, d = pcall(self.detector.getDimensionName)
            if dimOk and d then
                dimension = Text.prettifyName(d)
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
            hasDetector = self.detector ~= nil
        }
    end,

    render = function(self, data)
        local timeStr = formatTime(data.time)
        local timeOfDay, todColor = getTimeOfDay(data.time)

        -- Row 1: Title
        MonitorHelpers.writeCentered(self.monitor, 1, "CLOCK", colors.lightBlue)

        -- Row 3: Large time display
        MonitorHelpers.writeCentered(self.monitor, 3, timeStr, colors.white)

        -- Row 4: Time of day
        MonitorHelpers.writeCentered(self.monitor, 4, timeOfDay, todColor)

        -- Row 6: Weather
        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(1, 6)
        self.monitor.write("Weather: ")
        if data.weather == "thunder" then
            self.monitor.setTextColor(colors.yellow)
            self.monitor.write("Thunder")
        elseif data.weather == "rain" then
            self.monitor.setTextColor(colors.lightBlue)
            self.monitor.write("Rain")
        else
            self.monitor.setTextColor(colors.green)
            self.monitor.write("Clear")
        end

        -- Row 7: Moon (only at night)
        if data.time < 6 or data.time >= 20 then
            self.monitor.setTextColor(colors.white)
            self.monitor.setCursorPos(1, 7)
            self.monitor.write("Moon: ")
            self.monitor.setTextColor(colors.lightGray)
            local moonName = MOON_PHASES[data.moonPhase] or "Unknown"
            self.monitor.write(Text.truncateMiddle(moonName, self.width - 6))
        end

        -- Row 8: Biome
        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(1, 8)
        self.monitor.write("Biome: ")
        self.monitor.setTextColor(colors.lime)
        self.monitor.write(Text.truncateMiddle(data.biome, self.width - 7))

        -- Row 9: Dimension
        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(1, 9)
        self.monitor.write("Dim: ")
        self.monitor.setTextColor(colors.purple)
        self.monitor.write(Text.truncateMiddle(data.dimension, self.width - 5))

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
