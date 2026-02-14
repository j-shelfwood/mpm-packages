-- ResourceDetailOverlay.lua
-- Resource detail overlay for ResourceBrowserFactory
-- Shows resource info with optional crafting controls
-- Extracted from ResourceBrowserFactory.lua for maintainability

local Text = mpm('utils/Text')
local Core = mpm('ui/Core')

local ResourceDetailOverlay = {}

-- Generate craft amount labels
local function generateCraftLabels(amounts, unitDivisor, unitLabel)
    local labels = {}
    for _, amt in ipairs(amounts) do
        local displayAmt = amt / unitDivisor
        table.insert(labels, tostring(displayAmt) .. unitLabel)
    end
    return labels
end

-- Show resource detail overlay (blocking)
-- @param self View instance (needs monitor, peripheralName)
-- @param resource Resource data
-- @param config Factory config
function ResourceDetailOverlay.show(self, resource, config)
    local monitor = self.monitor
    local width, height = monitor.getSize()

    -- Calculate overlay bounds
    local overlayWidth = math.min(width - 2, 30)
    local overlayHeight = math.min(height - 2, 10)
    local x1 = math.floor((width - overlayWidth) / 2) + 1
    local y1 = math.floor((height - overlayHeight) / 2) + 1
    local x2 = x1 + overlayWidth - 1
    local y2 = y1 + overlayHeight - 1

    local monitorName = self.peripheralName
    local craftAmountIndex = 1
    local craftAmount = config.craftAmounts[1]
    local statusMessage = nil
    local statusColor = colors.gray

    -- Get labels
    local craftLabels = config.craftLabels or
        generateCraftLabels(config.craftAmounts, config.unitDivisor, config.unitLabel)

    while true do
        -- Draw background
        monitor.setBackgroundColor(colors.gray)
        for y = y1, y2 do
            monitor.setCursorPos(x1, y)
            monitor.write(string.rep(" ", overlayWidth))
        end

        -- Title bar
        local displayName = resource.displayName or Text.prettifyName(resource[config.idField] or "Unknown")
        monitor.setBackgroundColor(config.titleColor)
        monitor.setTextColor(colors.black)
        monitor.setCursorPos(x1, y1)
        monitor.write(string.rep(" ", overlayWidth))
        monitor.setCursorPos(x1 + 1, y1)
        monitor.write(Core.truncate(displayName, overlayWidth - 2))

        -- Content
        monitor.setBackgroundColor(colors.gray)
        local contentY = y1 + 2

        -- Current amount
        local rawAmount = resource[config.amountField] or 0
        local displayAmount = rawAmount / config.unitDivisor
        local amountColor = config.highlightColor
        if displayAmount == 0 then
            amountColor = colors.red
        elseif displayAmount < config.lowThreshold then
            amountColor = colors.orange
        end

        monitor.setTextColor(colors.white)
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.write(config.amountLabel or "Stock: ")
        monitor.setTextColor(amountColor)
        local amountStr = Text.formatNumber(displayAmount, 0)
        if config.unitLabel ~= "" then
            amountStr = amountStr .. " " .. config.unitLabel
        end
        monitor.write(amountStr)
        contentY = contentY + 1

        -- Registry name
        local registryName = resource[config.idField]
        if registryName then
            monitor.setTextColor(colors.lightGray)
            monitor.setCursorPos(x1 + 1, contentY)
            monitor.write(Core.truncate(registryName, overlayWidth - 2))
            contentY = contentY + 1
        end

        -- Craftable indicator and amount selector
        local isCraftable = resource.isCraftable or config.alwaysCraftable
        local amountSelectorY = contentY
        if isCraftable then
            contentY = contentY + 1
            amountSelectorY = contentY
            monitor.setTextColor(colors.white)
            monitor.setCursorPos(x1 + 1, contentY)
            monitor.write("Craft: ")

            -- Amount buttons
            local buttonX = x1 + 8
            for i, amt in ipairs(config.craftAmounts) do
                local label = craftLabels[i]
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
        if isCraftable then
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
            if isCraftable and ty == buttonY and tx >= x1 + 2 and tx <= x1 + 8 then
                local craftFn = config.getCraftFunction(self, resource)
                if craftFn then
                    local ok, result = pcall(function()
                        return craftFn({name = resource[config.idField], count = craftAmount})
                    end)

                    if ok and result then
                        local displayCraftAmount = craftAmount / config.unitDivisor
                        statusMessage = "Crafting " .. displayCraftAmount .. config.unitLabel .. " started"
                        statusColor = colors.lime
                    else
                        statusMessage = "Craft failed"
                        statusColor = colors.red
                    end
                else
                    statusMessage = config.craftUnavailableMessage or "Crafting unavailable"
                    statusColor = colors.red
                end
            end

            -- Amount selection (if craftable)
            if isCraftable and ty == amountSelectorY then
                local buttonX = x1 + 8
                for i, amt in ipairs(config.craftAmounts) do
                    local label = craftLabels[i]
                    if tx >= buttonX and tx < buttonX + #label + 2 then
                        craftAmount = amt
                        craftAmountIndex = i
                        break
                    end
                    buttonX = buttonX + #label + 3
                end
            end
        end
    end
end

return ResourceDetailOverlay
