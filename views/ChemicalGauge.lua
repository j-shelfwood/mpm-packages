-- ChemicalGauge.lua
-- Displays a single Mekanism chemical level as a vertical gauge
-- Requires: Applied Mekanistics addon for ME Bridge
-- Configurable: chemical to monitor, warning threshold
-- Touch to craft when craftable

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Core = mpm('ui/Core')
local Yield = mpm('utils/Yield')

-- Craft dialog overlay (blocking)
local function showCraftDialog(self, chemicalData)
    local monitor = self.monitor
    local width, height = monitor.getSize()

    -- Calculate overlay bounds
    local overlayWidth = math.min(width - 2, 24)
    local overlayHeight = math.min(height - 2, 8)
    local x1 = math.floor((width - overlayWidth) / 2) + 1
    local y1 = math.floor((height - overlayHeight) / 2) + 1
    local x2 = x1 + overlayWidth - 1
    local y2 = y1 + overlayHeight - 1

    local monitorName = self.peripheralName
    local craftAmount = 1000  -- 1 bucket default
    local statusMessage = nil
    local statusColor = colors.gray

    while true do
        -- Draw background
        monitor.setBackgroundColor(colors.gray)
        for y = y1, y2 do
            monitor.setCursorPos(x1, y)
            monitor.write(string.rep(" ", overlayWidth))
        end

        -- Title bar
        monitor.setBackgroundColor(colors.lightBlue)
        monitor.setTextColor(colors.black)
        monitor.setCursorPos(x1, y1)
        monitor.write(string.rep(" ", overlayWidth))
        monitor.setCursorPos(x1 + 1, y1)
        monitor.write(Core.truncate("Craft Chemical", overlayWidth - 2))

        -- Content
        monitor.setBackgroundColor(colors.gray)
        local contentY = y1 + 2

        -- Chemical name
        local chemicalName = Text.prettifyName(self.chemicalId)
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.write(Core.truncate(chemicalName, overlayWidth - 2))
        contentY = contentY + 1

        -- Amount selector (in buckets)
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.setTextColor(colors.lightGray)
        monitor.write("Amount: ")
        monitor.setTextColor(colors.yellow)
        monitor.write(tostring(craftAmount / 1000) .. "B")
        contentY = contentY + 1

        -- Amount buttons
        monitor.setCursorPos(x1 + 2, contentY)
        monitor.setBackgroundColor(colors.lightGray)
        monitor.setTextColor(colors.black)
        monitor.write(" -1B ")
        monitor.setCursorPos(x1 + 8, contentY)
        monitor.write(" +1B ")
        monitor.setCursorPos(x1 + 14, contentY)
        monitor.write(" +10B ")
        monitor.setBackgroundColor(colors.gray)

        -- Status message
        if statusMessage then
            monitor.setBackgroundColor(colors.gray)
            monitor.setTextColor(statusColor)
            monitor.setCursorPos(x1 + 1, y2 - 2)
            monitor.write(Core.truncate(statusMessage, overlayWidth - 2))
        end

        -- Action buttons
        local buttonY = y2 - 1
        monitor.setBackgroundColor(colors.gray)

        -- Craft button
        monitor.setTextColor(colors.lime)
        monitor.setCursorPos(x1 + 2, buttonY)
        monitor.write("[Craft]")

        -- Close button
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(x2 - 7, buttonY)
        monitor.write("[Close]")

        Core.resetColors(monitor)

        -- Wait for touch
        local event, side, tx, ty = os.pullEvent("monitor_touch")

        if side == monitorName then
            -- Close button or outside overlay
            if (ty == buttonY and tx >= x2 - 7 and tx <= x2 - 1) or
               tx < x1 or tx > x2 or ty < y1 or ty > y2 then
                return
            end

            -- Amount buttons
            if ty == y1 + 4 then
                if tx >= x1 + 2 and tx <= x1 + 6 then
                    craftAmount = math.max(1000, craftAmount - 1000)
                elseif tx >= x1 + 8 and tx <= x1 + 12 then
                    craftAmount = craftAmount + 1000
                elseif tx >= x1 + 14 and tx <= x1 + 19 then
                    craftAmount = craftAmount + 10000
                end
            end

            -- Craft button
            if ty == buttonY and tx >= x1 + 2 and tx <= x1 + 8 then
                if self.interface then
                    local filter = {
                        name = self.chemicalId,
                        count = craftAmount
                    }

                    local ok, result = pcall(function()
                        return self.interface:craftChemical(filter)
                    end)

                    if ok and result then
                        statusMessage = "Crafting " .. (craftAmount / 1000) .. "B"
                        statusColor = colors.lime
                    elseif ok then
                        statusMessage = "Cannot craft"
                        statusColor = colors.orange
                    else
                        statusMessage = "Craft failed"
                        statusColor = colors.red
                    end
                else
                    statusMessage = "No ME Bridge"
                    statusColor = colors.red
                end
            end
        end
    end
end

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
        self.lastChemicalData = nil
    end,

    getData = function(self)
        -- Check interface is available
        if not self.interface then return nil end

        if not self.chemicalId then
            return nil
        end

        -- Check if chemicals method exists (requires Applied Mekanistics)
        if not self.interface:hasChemicalSupport() then
            return { error = "addon" }
        end

        -- Fetch chemicals
        local chemicals = self.interface:chemicals()
        if not chemicals then return nil end

        Yield.yield()

        -- Find our chemical by registry name (with yields for large systems)
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

        -- Record history
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
        -- Show craft dialog if chemical is craftable
        if self.lastChemicalData and self.lastChemicalData.isCraftable then
            showCraftDialog(self, self.lastChemicalData)
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
