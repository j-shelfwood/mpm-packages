-- ChemicalGauge.lua
-- Displays a single Mekanism chemical level as a vertical gauge
-- Requires: Applied Mekanistics addon for ME Bridge
-- Configurable: chemical to monitor, warning threshold

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

return BaseView.custom({
    sleepTime = 1,

    configSchema = {
        {
            key = "chemical",
            type = "text",
            label = "Chemical ID",
            default = nil,
            required = true
        },
        {
            key = "warningBelow",
            type = "number",
            label = "Warning Below (mB)",
            default = 1000,
            min = 0,
            max = 1000000,
            presets = {100, 500, 1000, 5000, 10000}
        }
    },

    mount = function()
        local exists, bridge = AEInterface.exists()
        if not exists or not bridge then
            return false
        end

        -- Check if Applied Mekanistics addon is loaded (chemicals support)
        local hasChemicals = type(bridge.getChemicals) == "function"
        return hasChemicals
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil
        self.chemicalId = config.chemical
        self.warningBelow = config.warningBelow or 1000
        self.history = {}
        self.maxHistory = self.width
    end,

    getData = function(self)
        -- Check interface is available
        if not self.interface then return nil end

        if not self.chemicalId then
            return nil
        end

        -- Check if chemicals method exists
        if not self.interface.bridge.getChemicals then
            return { error = "addon" }
        end

        -- Fetch chemicals (direct bridge access)
        local chemicals = self.interface.bridge.getChemicals()
        if not chemicals then return nil end

        Yield.yield()

        -- Find our chemical by registry name (with yields for large systems)
        local amount = 0
        local chemicalId = self.chemicalId
        local count = 0
        for _, chemical in ipairs(chemicals) do
            if chemical.name == chemicalId then
                amount = chemical.count or chemical.amount or 0
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
        if data.error == "addon" then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Applied Mekanistics", colors.white)
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "addon not loaded", colors.gray)
            return
        end

        local buckets = data.buckets

        -- Determine color
        local gaugeColor = colors.lightBlue
        local isWarning = buckets < self.warningBelow

        if isWarning then
            gaugeColor = colors.red
        elseif buckets < self.warningBelow * 2 then
            gaugeColor = colors.orange
        end

        -- Row 1: Chemical name
        local name = Text.truncateMiddle(Text.prettifyName(self.chemicalId), self.width)
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
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Chemical Gauge", colors.white)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Configure to select chemical", colors.gray)
    end,

    errorMessage = "Error fetching chemicals"
})
