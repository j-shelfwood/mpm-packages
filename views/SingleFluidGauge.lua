-- SingleFluidGauge.lua
-- Displays a single fluid level as a vertical gauge
-- Configurable: fluid to monitor, warning threshold

local AEInterface = mpm('peripherals/AEInterface')

local module

-- Prettify fluid name for display
local function prettifyName(id)
    if not id then return "No Fluid" end
    local _, _, name = string.find(id, ":(.+)")
    if name then
        name = name:gsub("_", " ")
        return name:gsub("^%l", string.upper)
    end
    return id
end

-- Format fluid amount (buckets)
local function formatAmount(mB)
    if not mB then return "0B" end
    local buckets = mB / 1000
    if buckets >= 1000000 then
        return string.format("%.1fM", buckets / 1000000)
    elseif buckets >= 1000 then
        return string.format("%.1fK", buckets / 1000)
    else
        return string.format("%.0f", buckets) .. "B"
    end
end

module = {
    sleepTime = 1,

    -- Configuration schema for this view
    configSchema = {
        {
            key = "fluid",
            type = "fluid:id",
            label = "Fluid",
            default = nil,
            required = true
        },
        {
            key = "warningBelow",
            type = "number",
            label = "Warning Below",
            default = 1000,
            min = 0,
            max = 1000000,
            presets = {100, 500, 1000, 5000, 10000, 50000}
        }
    },

    new = function(monitor, config)
        config = config or {}
        local width, height = monitor.getSize()

        local self = {
            monitor = monitor,
            width = width,
            height = height,
            fluidId = config.fluid,
            warningBelow = config.warningBelow or 1000,
            interface = nil,
            history = {},
            maxHistory = width,
            initialized = false
        }

        -- Try to create interface
        local ok, interface = pcall(AEInterface.new)
        if ok and interface then
            self.interface = interface
        end

        return self
    end,

    mount = function()
        return AEInterface.exists()
    end,

    render = function(self)
        -- One-time initialization
        if not self.initialized then
            self.monitor.clear()
            self.initialized = true
        end

        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)

        -- Check interface
        if not self.interface then
            self.monitor.setCursorPos(1, math.floor(self.height / 2))
            self.monitor.write("No AE2 peripheral")
            return
        end

        -- Check if fluid is configured
        if not self.fluidId then
            self.monitor.setCursorPos(1, math.floor(self.height / 2) - 1)
            self.monitor.write("Fluid Gauge")
            self.monitor.setCursorPos(1, math.floor(self.height / 2) + 1)
            self.monitor.write("Configure to select fluid")
            return
        end

        -- Fetch fluids
        local ok, fluids = pcall(AEInterface.fluids, self.interface)
        if not ok or not fluids then
            self.monitor.setCursorPos(1, 1)
            self.monitor.setTextColor(colors.red)
            self.monitor.write("Error fetching fluids")
            return
        end

        -- Find our fluid
        local amount = 0
        for _, fluid in ipairs(fluids) do
            if fluid.name == self.fluidId then
                amount = fluid.amount or 0
                break
            end
        end

        local buckets = amount / 1000

        -- Record history
        table.insert(self.history, buckets)
        if #self.history > self.maxHistory then
            table.remove(self.history, 1)
        end

        -- Determine color based on warning threshold
        local gaugeColor = colors.cyan
        local isWarning = buckets < self.warningBelow

        if isWarning then
            gaugeColor = colors.red
        elseif buckets < self.warningBelow * 2 then
            gaugeColor = colors.orange
        end

        -- Clear screen
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.clear()

        -- Row 1: Fluid name
        local name = prettifyName(self.fluidId)
        if #name > self.width then
            name = name:sub(1, self.width - 3) .. "..."
        end
        self.monitor.setTextColor(colors.white)
        local nameX = math.floor((self.width - #name) / 2) + 1
        self.monitor.setCursorPos(nameX, 1)
        self.monitor.write(name)

        -- Row 2: Amount (large, centered)
        local amountStr = formatAmount(amount)
        self.monitor.setTextColor(gaugeColor)
        local amountX = math.floor((self.width - #amountStr) / 2) + 1
        self.monitor.setCursorPos(amountX, 3)
        self.monitor.write(amountStr)

        -- Warning indicator
        if isWarning then
            self.monitor.setTextColor(colors.red)
            local warnText = "LOW!"
            self.monitor.setCursorPos(math.floor((self.width - #warnText) / 2) + 1, 4)
            self.monitor.write(warnText)
        end

        -- Vertical gauge bar (if room)
        if self.height >= 8 then
            local barStartY = 6
            local barHeight = self.height - barStartY - 1
            local barX = math.floor(self.width / 2)

            -- Calculate fill based on history max (auto-scaling)
            local maxBuckets = buckets
            for _, h in ipairs(self.history) do
                if h > maxBuckets then maxBuckets = h end
            end
            maxBuckets = math.max(maxBuckets, self.warningBelow * 2)  -- At least 2x warning threshold

            local fillHeight = math.floor((buckets / maxBuckets) * barHeight)

            -- Draw bar background
            self.monitor.setBackgroundColor(colors.gray)
            for y = barStartY, barStartY + barHeight - 1 do
                self.monitor.setCursorPos(barX - 1, y)
                self.monitor.write("   ")
            end

            -- Draw bar fill (from bottom up)
            self.monitor.setBackgroundColor(gaugeColor)
            for y = 0, fillHeight - 1 do
                local drawY = barStartY + barHeight - 1 - y
                if drawY >= barStartY then
                    self.monitor.setCursorPos(barX - 1, drawY)
                    self.monitor.write("   ")
                end
            end

            -- Warning line marker
            local warningY = barStartY + barHeight - 1 - math.floor((self.warningBelow / maxBuckets) * barHeight)
            if warningY >= barStartY and warningY < barStartY + barHeight then
                self.monitor.setBackgroundColor(colors.black)
                self.monitor.setTextColor(colors.red)
                self.monitor.setCursorPos(barX + 2, warningY)
                self.monitor.write("<")
            end
        end

        -- Bottom: threshold info
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.gray)
        local thresholdStr = "Warn <" .. self.warningBelow .. "B"
        self.monitor.setCursorPos(1, self.height)
        self.monitor.write(thresholdStr)

        -- Reset colors
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)
    end
}

return module
