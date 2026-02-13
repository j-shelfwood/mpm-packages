-- ItemBrowser.lua
-- Full ME network inventory browser with search and interactive details
-- Touch an item to see details and craft if available

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local Core = mpm('ui/Core')
local Yield = mpm('utils/Yield')

-- Item detail overlay (blocking)
local function showItemDetail(self, item)
    local monitor = self.monitor
    local width, height = monitor.getSize()

    -- Calculate overlay bounds
    local overlayWidth = math.min(width - 2, 30)
    local overlayHeight = math.min(height - 2, 9)
    local x1 = math.floor((width - overlayWidth) / 2) + 1
    local y1 = math.floor((height - overlayHeight) / 2) + 1
    local x2 = x1 + overlayWidth - 1
    local y2 = y1 + overlayHeight - 1

    local monitorName = peripheral.getName(monitor)
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
        local displayName = item.displayName or Text.prettifyName(item.registryName or "Unknown")
        monitor.setBackgroundColor(colors.lightGray)
        monitor.setTextColor(colors.black)
        monitor.setCursorPos(x1, y1)
        monitor.write(string.rep(" ", overlayWidth))
        monitor.setCursorPos(x1 + 1, y1)
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

        -- Craftable indicator and amount selector
        if item.isCraftable then
            contentY = contentY + 1
            monitor.setTextColor(colors.white)
            monitor.setCursorPos(x1 + 1, contentY)
            monitor.write("Craft: ")

            -- Amount buttons
            local amounts = {1, 16, 64}
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

        -- Craft button (only if craftable)
        if item.isCraftable then
            monitor.setTextColor(colors.lime)
            monitor.setCursorPos(x1 + 2, buttonY)
            monitor.write("[Craft]")
        end

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
            if item.isCraftable and ty == buttonY and tx >= x1 + 2 and tx <= x1 + 8 then
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

            -- Amount selection (if craftable)
            if item.isCraftable and ty == contentY then
                local amounts = {1, 16, 64}
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
            key = "sortBy",
            type = "select",
            label = "Sort By",
            options = {
                { value = "count", label = "Count (High)" },
                { value = "count_asc", label = "Count (Low)" },
                { value = "name", label = "Name (A-Z)" }
            },
            default = "count"
        },
        {
            key = "minCount",
            type = "number",
            label = "Min Count",
            default = 0,
            min = 0,
            max = 10000,
            presets = {0, 1, 64, 1000}
        }
    },

    mount = function()
        return AEInterface.exists()
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil
        self.sortBy = config.sortBy or "count"
        self.minCount = config.minCount or 0
        self.totalItems = 0
    end,

    getData = function(self)
        if not self.interface then return nil end

        local items = self.interface:items()
        if not items then return {} end

        self.totalItems = #items

        Yield.yield()

        -- Filter by minimum count
        local filtered = {}
        for _, item in ipairs(items) do
            if (item.count or 0) >= self.minCount then
                table.insert(filtered, item)
            end
        end

        Yield.yield()

        -- Sort
        if self.sortBy == "count" then
            table.sort(filtered, function(a, b)
                return (a.count or 0) > (b.count or 0)
            end)
        elseif self.sortBy == "count_asc" then
            table.sort(filtered, function(a, b)
                return (a.count or 0) < (b.count or 0)
            end)
        elseif self.sortBy == "name" then
            table.sort(filtered, function(a, b)
                local nameA = a.displayName or a.registryName or ""
                local nameB = b.displayName or b.registryName or ""
                return nameA < nameB
            end)
        end

        return filtered
    end,

    header = function(self, data)
        return {
            text = "ITEMS",
            color = colors.cyan,
            secondary = " (" .. #data .. "/" .. self.totalItems .. ")",
            secondaryColor = colors.gray
        }
    end,

    formatItem = function(self, item)
        local count = item.count or 0
        local countStr = Text.formatNumber(count)

        local nameColor = colors.white
        local countColor = colors.gray

        -- Highlight craftable items
        if item.isCraftable then
            nameColor = colors.lime
        end

        -- Highlight low counts
        if count == 0 then
            countColor = colors.red
        elseif count < 64 then
            countColor = colors.orange
        end

        return {
            lines = {
                item.displayName or Text.prettifyName(item.registryName or "Unknown"),
                countStr
            },
            colors = { nameColor, countColor },
            touchAction = "detail",
            touchData = item
        }
    end,

    onItemTouch = function(self, item, action)
        showItemDetail(self, item)
    end,

    footer = function(self, data)
        return {
            text = "Touch for details",
            color = colors.gray
        }
    end,

    emptyMessage = "No items in storage"
})
