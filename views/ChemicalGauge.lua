-- ChemicalGauge.lua
-- Displays a single Mekanism chemical level as a vertical gauge
-- Requires: Applied Mekanistics addon for ME Bridge
-- Touch to craft when craftable

local BaseView = mpm('views/BaseView')
local AEViewSupport = mpm('views/AEViewSupport')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local CraftDialog = mpm('ui/CraftDialog')
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
        if not AEViewSupport.mount() then
            return false
        end
        local probe = {}
        local interface = AEViewSupport.init(probe)
        return interface ~= nil and interface:hasChemicalSupport() == true
    end,

    init = function(self, config)
        AEViewSupport.init(self)
        self.chemicalId = config.chemical
        self.warningBelow = config.warningBelow or 1000
        self.history = {}
        self.maxHistory = self.width
        self.lastChemicalData = nil
    end,

    getData = function(self)
        -- Lazy re-init: retry if host not yet discovered at init time
        if not AEViewSupport.ensureInterface(self) then return nil end
        if not self.chemicalId then return nil end

        if not self.interface:hasChemicalSupport() then
            return { error = "addon" }
        end

        local chemicals = self.interface:chemicals()
        if not chemicals then return nil end

        local amount = 0
        local isCraftable = false
        local chemicalId = self.chemicalId
        local count = 0

        for _, chemical in ipairs(chemicals) do
            if chemical.name == chemicalId then
                amount = chemical.count or chemical.amount or 0
                isCraftable = chemical.isCraftable or false
                break
            end
            count = count + 1
            Yield.check(count)
        end

        local buckets = amount / 1000

        MonitorHelpers.recordHistory(self.history, buckets, self.maxHistory)

        local data = {
            buckets = buckets,
            isCraftable = isCraftable,
            history = self.history
        }
        self.lastChemicalData = data
        return data
    end,

    render = function(self, data)
        if data.error == "addon" then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Applied Mekanistics", colors.white)
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "addon not loaded", colors.gray)
            return
        end

        local buckets = data.buckets
        local isWarning = buckets < self.warningBelow

        -- Determine color
        local gaugeColor = colors.lightBlue
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

        -- Warning indicator or craftable hint
        if isWarning then
            MonitorHelpers.writeCentered(self.monitor, 4, "LOW!", colors.red)
        elseif data.isCraftable then
            MonitorHelpers.writeCentered(self.monitor, 4, "[Touch to Craft]", colors.lime)
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

    onTouch = function(self, x, y)
        if self.lastChemicalData and self.lastChemicalData.isCraftable then
            CraftDialog.show(self.monitor, self.peripheralName, {
                preset = "chemical",
                resourceName = Text.prettifyName(self.chemicalId),
                resourceId = self.chemicalId,
                craftFunction = function(filter)
                    return self.interface:craftChemical(filter)
                end
            })
            return true
        end
        return false
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Chemical Gauge", colors.white)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Configure to select chemical", colors.gray)
    end,

    errorMessage = "Error fetching chemicals"
})
