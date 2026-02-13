-- CraftableItems.lua
-- Interactive browser for craftable items with one-tap crafting
-- Touch an item to see details and trigger crafting
-- Replaces LowStock.lua functionality via showMode config

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local Core = mpm('ui/Core')
local Yield = mpm('utils/Yield')

-- Item detail overlay with craft button (blocking)
local function showItemDetail(self, item)
    local monitor = self.monitor
    local width, height = monitor.getSize()

    -- Calculate overlay bounds
    local overlayWidth = math.min(width - 2, 30)
    local overlayHeight = math.min(height - 2, 10)
    local x1 = math.floor((width - overlayWidth) / 2) + 1
    local y1 = math.floor((height - overlayHeight) / 2) + 1
    local x2 = x1 + overlayWidth - 1
    local y2 = y1 + overlayHeight - 1

    -- Use stored peripheral name (monitor is a window buffer, not a peripheral)
    local monitorName = self.peripheralName
    local craftAmount = 1
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
        monitor.setBackgroundColor(colors.lightGray)
        monitor.setTextColor(colors.black)
        monitor.setCursorPos(x1, y1)
        monitor.write(string.rep(" ", overlayWidth))
        monitor.setCursorPos(x1 + 1, y1)
        local displayName = item.displayName or Text.prettifyName(item.registryName or "Unknown")
        monitor.write(Core.truncate(displayName, overlayWidth - 2))

        -- Content
        monitor.setBackgroundColor(colors.gray)
        local contentY = y1 + 2

        -- Current stock
        local count = item.count or 0
        local countColor = colors.lime
        if count == 0 then
            countColor = colors.red
        elseif count < 64 then
            countColor = colors.orange
        end

        monitor.setTextColor(colors.white)
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.write("Stock: ")
        monitor.setTextColor(countColor)
        monitor.write(Text.formatNumber(count))
        contentY = contentY + 1

        -- Registry name
        if item.registryName then
            monitor.setTextColor(colors.lightGray)
            monitor.setCursorPos(x1 + 1, contentY)
            monitor.write(Core.truncate(item.registryName, overlayWidth - 2))
            contentY = contentY + 1
        end

        -- Craft amount selector
        contentY = contentY + 1
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.write("Craft: ")

        -- Amount buttons
        local amounts = {1, 16, 64, 256}
        local buttonX = x1 + 8
        for _, amt in ipairs(amounts) do
            local label = tostring(amt)
            if amt == craftAmount then
                monitor.setBackgroundColor(colors.cyan)
                monitor.setTextColor(colors.black)
            else
                monitor.setBackgroundColor(colors.lightGray)
                monitor.setTextColor(colors.gray)
            end
            monitor.setCursorPos(buttonX, contentY)
            monitor.write(" " .. label .. " ")
            buttonX = buttonX + #label + 3
        end

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
        monitor.setTextColor(colors.red)
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

            -- Craft button
            if ty == buttonY and tx >= x1 + 2 and tx <= x1 + 8 then
                -- Trigger crafting
                if self.interface then
                    local ok, result = pcall(function()
                        return self.interface:craftItem({name = item.registryName, count = craftAmount})
                    end)

                    if ok and result then
                        statusMessage = "Crafting " .. craftAmount .. "x started"
                        statusColor = colors.lime
                    else
                        statusMessage = "Craft failed"
                        statusColor = colors.red
                    end
                else
                    statusMessage = "No ME Bridge"
                    statusColor = colors.red
                end
            end

            -- Amount selection
            if ty == contentY then
                buttonX = x1 + 8
                for _, amt in ipairs(amounts) do
                    local label = tostring(amt)
                    if tx >= buttonX and tx < buttonX + #label + 2 then
                        craftAmount = amt
                        break
                    end
                    buttonX = buttonX + #label + 3
                end
            end
        end
    end
end

return BaseView.interactive({
    sleepTime = 5,

    configSchema = {
        {
            key = "showMode",
            type = "select",
            label = "Show",
            options = {
                { value = "all", label = "All Craftable" },
                { value = "lowStock", label = "Low Stock Only" },
                { value = "zeroStock", label = "Out of Stock" }
            },
            default = "all"
        },
        {
            key = "lowThreshold",
            type = "number",
            label = "Low Stock Threshold",
            default = 64,
            min = 1,
            max = 1000,
            presets = {16, 32, 64, 128, 256}
        }
    },

    mount = function()
        return AEInterface.exists()
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil
        self.showMode = config.showMode or "all"
        self.lowThreshold = config.lowThreshold or 64
        self.totalCraftable = 0
    end,

    getData = function(self)
        if not self.interface then return nil end

        -- Get craftable items from ME Bridge
        local craftableItems = self.interface.bridge.getCraftableItems()
        if not craftableItems then return {} end

        Yield.yield()

        self.totalCraftable = #craftableItems

        -- Get current stock levels
        local allItems = self.interface:items()
        if not allItems then return {} end

        Yield.yield()

        -- Build lookup for stock counts
        local stockLookup = {}
        for _, item in ipairs(allItems) do
            if item.registryName then
                stockLookup[item.registryName] = item.count or 0
            end
        end

        -- Combine data: craftable items with current stock
        local displayItems = {}
        for _, craftable in ipairs(craftableItems) do
            if craftable.name then
                local count = stockLookup[craftable.name] or 0

                -- Apply filter based on showMode
                local include = false
                if self.showMode == "all" then
                    include = true
                elseif self.showMode == "zeroStock" then
                    include = (count == 0)
                elseif self.showMode == "lowStock" then
                    include = (count < self.lowThreshold)
                end

                if include then
                    table.insert(displayItems, {
                        registryName = craftable.name,
                        displayName = craftable.displayName or craftable.name,
                        count = count,
                        isCraftable = true
                    })
                end
            end
        end

        Yield.yield()

        -- Sort by count (lowest first)
        table.sort(displayItems, function(a, b)
            if a.count == b.count then
                return (a.displayName or "") < (b.displayName or "")
            end
            return a.count < b.count
        end)

        return displayItems
    end,

    header = function(self, data)
        local headerText = "CRAFTABLE"
        local headerColor = colors.cyan

        if self.showMode == "zeroStock" then
            headerText = "OUT OF STOCK"
            headerColor = colors.red
        elseif self.showMode == "lowStock" then
            headerText = "LOW STOCK"
            headerColor = colors.orange
        end

        return {
            text = headerText,
            color = headerColor,
            secondary = " (" .. #data .. "/" .. self.totalCraftable .. ")",
            secondaryColor = colors.gray
        }
    end,

    formatItem = function(self, item)
        local count = item.count or 0
        local countColor = colors.lime

        if count == 0 then
            countColor = colors.red
        elseif count < 64 then
            countColor = colors.orange
        end

        return {
            lines = {
                item.displayName or Text.prettifyName(item.registryName or "Unknown"),
                Text.formatNumber(count)
            },
            colors = { colors.white, countColor },
            touchAction = "detail",
            touchData = item
        }
    end,

    onItemTouch = function(self, item, action)
        -- Show item detail overlay with craft button (blocking)
        showItemDetail(self, item)
    end,

    footer = function(self, data)
        return {
            text = "Touch to craft",
            color = colors.gray
        }
    end,

    emptyMessage = "No craftable items"
})
