-- ItemGauge.lua
-- Displays a single item count with large gauge display
-- Configurable: item to monitor, warning threshold
-- Touch to craft when craftable
-- Naming consistent with FluidGauge, ChemicalGauge

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Core = mpm('ui/Core')
local Yield = mpm('utils/Yield')

-- Craft dialog overlay (blocking)
local function showCraftDialog(self, itemData)
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
    local craftAmount = 64
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
        monitor.write(Core.truncate("Craft Item", overlayWidth - 2))

        -- Content
        monitor.setBackgroundColor(colors.gray)
        local contentY = y1 + 2

        -- Item name
        local itemName = Text.prettifyName(self.itemId)
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.write(Core.truncate(itemName, overlayWidth - 2))
        contentY = contentY + 1

        -- Amount selector
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.setTextColor(colors.lightGray)
        monitor.write("Amount: ")
        monitor.setTextColor(colors.yellow)
        monitor.write(tostring(craftAmount))
        contentY = contentY + 1

        -- Amount buttons
        monitor.setCursorPos(x1 + 2, contentY)
        monitor.setBackgroundColor(colors.lightGray)
        monitor.setTextColor(colors.black)
        monitor.write(" -10 ")
        monitor.setCursorPos(x1 + 8, contentY)
        monitor.write(" +10 ")
        monitor.setCursorPos(x1 + 14, contentY)
        monitor.write(" +64 ")
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
                    craftAmount = math.max(1, craftAmount - 10)
                elseif tx >= x1 + 8 and tx <= x1 + 12 then
                    craftAmount = craftAmount + 10
                elseif tx >= x1 + 14 and tx <= x1 + 18 then
                    craftAmount = craftAmount + 64
                end
            end

            -- Craft button
            if ty == buttonY and tx >= x1 + 2 and tx <= x1 + 8 then
                if self.interface then
                    local filter = {
                        name = self.itemId,
                        count = craftAmount
                    }

                    local ok, result = pcall(function()
                        return self.interface:craftItem(filter)
                    end)

                    if ok and result then
                        statusMessage = "Crafting " .. craftAmount .. "x"
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
            key = "item",
            type = "item:id",
            label = "Item",
            default = nil,
            required = true
        },
        {
            key = "warningBelow",
            type = "number",
            label = "Warning Below",
            default = 100,
            min = 0,
            max = 1000000,
            presets = {10, 50, 100, 500, 1000, 10000}
        }
    },

    mount = function()
        return AEInterface.exists()
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil
        self.itemId = config.item
        self.warningBelow = config.warningBelow or 100
        self.prevCount = nil
        self.changeIndicator = ""
        self.lastItemData = nil
    end,

    getData = function(self)
        -- Check interface is available
        if not self.interface then return nil end

        if not self.itemId then
            return nil
        end

        -- Fetch items
        local items = self.interface:items()
        if not items then return nil end

        Yield.yield()

        -- Find our item by registry name (with yields for large systems)
        local count = 0
        local isCraftable = false
        local itemId = self.itemId
        local iterCount = 0
        for _, item in ipairs(items) do
            if item.registryName == itemId then
                count = item.count or 0
                isCraftable = item.isCraftable or false
                break
            end
            iterCount = iterCount + 1
            Yield.check(iterCount)
        end

        -- Track change direction
        if self.prevCount ~= nil then
            if count > self.prevCount then
                self.changeIndicator = "+"
            elseif count < self.prevCount then
                self.changeIndicator = "-"
            else
                self.changeIndicator = ""
            end
        end
        self.prevCount = count

        local data = {
            count = count,
            isCraftable = isCraftable,
            changeIndicator = self.changeIndicator
        }
        self.lastItemData = data
        return data
    end,

    render = function(self, data)
        local count = data.count

        -- Determine color based on warning threshold
        local countColor = colors.white
        local isWarning = count < self.warningBelow

        if isWarning then
            countColor = colors.red
        elseif count < self.warningBelow * 2 then
            countColor = colors.orange
        elseif count >= self.warningBelow * 10 then
            countColor = colors.lime
        end

        -- Row 1: Item name (prettified from registry name)
        local name = Text.truncateMiddle(Text.prettifyName(self.itemId), self.width)
        MonitorHelpers.writeCentered(self.monitor, 1, name, colors.white)

        -- Center: Large count
        local countStr = Text.formatNumber(count, 0)
        local centerY = math.floor(self.height / 2)
        MonitorHelpers.writeCentered(self.monitor, centerY, countStr, countColor)

        -- Change indicator
        if data.changeIndicator ~= "" then
            local indicatorColor = data.changeIndicator == "+" and colors.green or colors.red
            local countX = math.floor((self.width - #countStr) / 2) + 1
            if countX + #countStr + 1 <= self.width then
                self.monitor.setTextColor(indicatorColor)
                self.monitor.setCursorPos(countX + #countStr + 1, centerY)
                self.monitor.write(data.changeIndicator)
            end
        end

        -- Warning/Status row
        local statusY = centerY + 2
        if statusY <= self.height - 1 then
            if isWarning then
                MonitorHelpers.writeCentered(self.monitor, statusY, "LOW STOCK!", colors.red)
            elseif data.isCraftable then
                MonitorHelpers.writeCentered(self.monitor, statusY, "[Touch to Craft]", colors.lime)
            end
        end

        -- Bottom: threshold info
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(1, self.height)
        self.monitor.write("Warn <" .. self.warningBelow)

        self.monitor.setTextColor(colors.white)
    end,

    onTouch = function(self, x, y)
        -- Show craft dialog if item is craftable
        if self.lastItemData and self.lastItemData.isCraftable then
            showCraftDialog(self, self.lastItemData)
            return true
        end
        return false
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Item Counter", colors.white)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Configure to select item", colors.gray)
    end,

    errorMessage = "Error fetching items"
})
