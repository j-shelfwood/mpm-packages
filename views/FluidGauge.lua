-- FluidGauge.lua
-- Displays a single fluid level as a vertical gauge
-- Configurable: fluid to monitor, warning threshold

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

return BaseView.custom({
    sleepTime = 1,

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
            label = "Warning Below (B)",
            default = 1000,
            min = 0,
            max = 1000000,
            presets = {100, 500, 1000, 5000, 10000, 50000}
        }
    },

    mount = function()
        return AEInterface.exists()
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil
        self.fluidId = config.fluid
        self.warningBelow = config.warningBelow or 1000
        self.history = {}
        self.maxHistory = self.width
    end,

    getData = function(self)
        -- Check interface is available
        if not self.interface then return nil end

        if not self.fluidId then
            return nil
        end

        -- Fetch fluids
        local fluids = self.interface:fluids()
        if not fluids then return nil end

        Yield.yield()

        -- Find our fluid by registry name (with yields for large systems)
        local amount = 0
        local fluidId = self.fluidId
        local count = 0
        for _, fluid in ipairs(fluids) do
            if fluid.registryName == fluidId then
                amount = fluid.amount or 0
                break
            end
            count = count + 1
            Yield.check(count)
        end

        local buckets = amount / 1000

        -- Record history
        MonitorHelpers.recordHistory(self.history, buckets, self.maxHistory)

        return {
            buckets = buckets,
            history = self.history
        }
    end,

    render = function(self, data)
        local buckets = data.buckets

        -- Determine color
        local gaugeColor = colors.cyan
        local isWarning = buckets < self.warningBelow

        if isWarning then
            gaugeColor = colors.red
        elseif buckets < self.warningBelow * 2 then
            gaugeColor = colors.orange
        end

        -- Row 1: Fluid name
        local name = Text.truncateMiddle(Text.prettifyName(self.fluidId), self.width)
        MonitorHelpers.writeCentered(self.monitor, 1, name, colors.white)

        -- Row 3: Amount
        local amountStr = Text.formatNumber(buckets, 0) .. "B"
        MonitorHelpers.writeCentered(self.monitor, 3, amountStr, gaugeColor)

        -- Warning indicator
        if isWarning then
            MonitorHelpers.writeCentered(self.monitor, 4, "LOW!", colors.red)
        end

        -- Vertical gauge bar (if room)
        if self.height >= 8 then
            local barStartY = 6
            local barHeight = self.height - barStartY - 1
            local barX = math.floor(self.width / 2)

            -- Auto-scaling based on history
            local maxBuckets = buckets
            for _, h in ipairs(self.history) do
                if h > maxBuckets then maxBuckets = h end
            end
            maxBuckets = math.max(maxBuckets, self.warningBelow * 2)

            local fillHeight = math.floor((buckets / maxBuckets) * barHeight)

            -- Bar background
            self.monitor.setBackgroundColor(colors.gray)
            for y = barStartY, barStartY + barHeight - 1 do
                self.monitor.setCursorPos(barX - 1, y)
                self.monitor.write("   ")
            end

            -- Bar fill (from bottom)
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
        self.monitor.setCursorPos(1, self.height)
        self.monitor.write("Warn <" .. self.warningBelow .. "B")

        self.monitor.setTextColor(colors.white)
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Fluid Gauge", colors.white)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Configure to select fluid", colors.gray)
    end,

    errorMessage = "Error fetching fluids"
})
