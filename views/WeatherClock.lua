-- WeatherClock.lua
-- Displays Minecraft time, weather, moon phase, and biome
-- Supports: environment_detector (Advanced Peripherals)
-- Falls back to os.time() if no detector available

local module

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

module = {
    sleepTime = 1,

    new = function(monitor, config)
        local width, height = monitor.getSize()
        local self = {
            monitor = monitor,
            detector = nil,
            width = width,
            height = height,
            initialized = false
        }

        -- Try to find environment detector
        local detector = peripheral.find("environment_detector")
        if detector then
            self.detector = detector
        end

        return self
    end,

    mount = function()
        -- Always mount - can fall back to os.time()
        return true
    end,

    -- Clear a single line by overwriting with spaces
    clearLine = function(self, y)
        self.monitor.setCursorPos(1, y)
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.write(string.rep(" ", self.width))
    end,

    -- Write text at position with optional padding
    writeAt = function(self, x, y, text, padWidth)
        self.monitor.setCursorPos(x, y)
        if padWidth then
            text = text .. string.rep(" ", math.max(0, padWidth - #text))
        end
        self.monitor.write(text)
    end,

    formatTime = function(time)
        -- time is 0-24 in Minecraft
        local hours = math.floor(time)
        local minutes = math.floor((time - hours) * 60)
        local period = "AM"

        if hours >= 12 then
            period = "PM"
            if hours > 12 then
                hours = hours - 12
            end
        end
        if hours == 0 then
            hours = 12
        end

        return string.format("%d:%02d %s", hours, minutes, period)
    end,

    getTimeOfDay = function(time)
        if time >= 6 and time < 12 then
            return "Morning", colors.yellow
        elseif time >= 12 and time < 17 then
            return "Afternoon", colors.orange
        elseif time >= 17 and time < 20 then
            return "Evening", colors.orange
        else
            return "Night", colors.blue
        end
    end,

    render = function(self)
        -- One-time initialization
        if not self.initialized then
            self.monitor.clear()
            self.initialized = true
        end

        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)

        local time = 12  -- Default noon
        local weather = "clear"
        local isRaining = false
        local isThundering = false
        local moonPhase = 0
        local biome = "Unknown"
        local dimension = "Overworld"

        -- Try to get data from detector
        if self.detector then
            -- Time
            local ok, t = pcall(self.detector.getTime)
            if ok and t then
                time = t / 1000  -- Convert to 0-24 format
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
                -- Clean up biome name (minecraft:plains -> Plains)
                local _, _, name = string.find(b, ":(.+)")
                if name then
                    name = name:gsub("_", " ")
                    biome = name:gsub("^%l", string.upper)
                else
                    biome = b
                end
            end

            -- Dimension
            local dimOk, d = pcall(self.detector.getDimensionName)
            if dimOk and d then
                local _, _, name = string.find(d, ":(.+)")
                if name then
                    dimension = name:gsub("_", " "):gsub("^%l", string.upper)
                else
                    dimension = d
                end
            end
        else
            -- Fallback to CC time
            time = os.time()
        end

        local timeStr = module.formatTime(time)
        local timeOfDay, todColor = module.getTimeOfDay(time)

        -- Center the display
        local centerX = math.floor(self.width / 2)

        -- Row 1: Title
        module.clearLine(self, 1)
        self.monitor.setTextColor(colors.lightBlue)
        local titleText = "WEATHER CLOCK"
        module.writeAt(self, centerX - math.floor(#titleText / 2), 1, titleText)

        -- Row 3: Large time display
        module.clearLine(self, 3)
        self.monitor.setTextColor(colors.white)
        local timeX = centerX - math.floor(#timeStr / 2)
        module.writeAt(self, math.max(1, timeX), 3, timeStr)

        -- Row 4: Time of day
        module.clearLine(self, 4)
        self.monitor.setTextColor(todColor)
        local todX = centerX - math.floor(#timeOfDay / 2)
        module.writeAt(self, math.max(1, todX), 4, timeOfDay)

        -- Row 6: Weather
        module.clearLine(self, 6)
        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(1, 6)
        self.monitor.write("Weather: ")
        if weather == "thunder" then
            self.monitor.setTextColor(colors.yellow)
            self.monitor.write("Thunderstorm")
        elseif weather == "rain" then
            self.monitor.setTextColor(colors.lightBlue)
            self.monitor.write("Raining")
        else
            self.monitor.setTextColor(colors.green)
            self.monitor.write("Clear")
        end
        -- Pad to clear old text
        local curX, _ = self.monitor.getCursorPos()
        self.monitor.write(string.rep(" ", self.width - curX))

        -- Row 7: Moon phase (only show at night)
        module.clearLine(self, 7)
        if time < 6 or time >= 20 then
            self.monitor.setTextColor(colors.white)
            self.monitor.setCursorPos(1, 7)
            self.monitor.write("Moon: ")
            self.monitor.setTextColor(colors.lightGray)
            self.monitor.write(MOON_PHASES[moonPhase] or "Unknown")
        end

        -- Row 8: Biome
        module.clearLine(self, 8)
        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(1, 8)
        self.monitor.write("Biome: ")
        self.monitor.setTextColor(colors.lime)
        self.monitor.write(biome)

        -- Row 9: Dimension
        module.clearLine(self, 9)
        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(1, 9)
        self.monitor.write("Dim: ")
        self.monitor.setTextColor(colors.purple)
        self.monitor.write(dimension)

        -- Bottom row: Detector status
        module.clearLine(self, self.height)
        self.monitor.setTextColor(colors.gray)
        if self.detector then
            module.writeAt(self, 1, self.height, "Env Detector: OK")
        else
            module.writeAt(self, 1, self.height, "No detector (CC time)")
        end

        self.monitor.setTextColor(colors.white)
    end
}

return module
