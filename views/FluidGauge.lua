-- FluidGauge.lua
-- Displays a single fluid level as a vertical gauge
-- Configurable: fluid to monitor, warning threshold
-- Touch to craft when craftable

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Core = mpm('ui/Core')
local Yield = mpm('utils/Yield')

-- Craft dialog overlay (blocking)
local function showCraftDialog(self, fluidData)
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
        monitor.setBackgroundColor(colors.cyan)
        monitor.setTextColor(colors.black)
        monitor.setCursorPos(x1, y1)
        monitor.write(string.rep(" ", overlayWidth))
        monitor.setCursorPos(x1 + 1, y1)
        monitor.write(Core.truncate("Craft Fluid", overlayWidth - 2))

        -- Content
        monitor.setBackgroundColor(colors.gray)
        local contentY = y1 + 2

        -- Fluid name
        local fluidName = Text.prettifyName(self.fluidId)
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.write(Core.truncate(fluidName, overlayWidth - 2))
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
                        name = self.fluidId,
                        count = craftAmount
                    }

                    local ok, result = pcall(function()
                        return self.interface:craftFluid(filter)
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
        self.lastFluidData = nil
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
        local isCraftable = false
        local fluidId = self.fluidId
        local count = 0
        for _, fluid in ipairs(fluids) do
            if fluid.registryName == fluidId then
                amount = fluid.amount or 0
                isCraftable = fluid.isCraftable or false
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
        self.lastFluidData = data
        return data
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
        -- Show craft dialog if fluid is craftable
        if self.lastFluidData and self.lastFluidData.isCraftable then
            showCraftDialog(self, self.lastFluidData)
            return true
        end
        return false
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Fluid Gauge", colors.white)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Configure to select fluid", colors.gray)
    end,

    errorMessage = "Error fetching fluids"
})
