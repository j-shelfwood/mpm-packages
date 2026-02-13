-- CraftDialog.lua
-- Reusable crafting dialog for item/fluid/chemical crafting
-- Provides amount selection and craft action with status feedback

local Core = mpm('ui/Core')

local CraftDialog = {}

-- Configuration presets for different resource types
CraftDialog.PRESETS = {
    item = {
        title = "Craft Item",
        titleColor = colors.cyan,
        unitLabel = "",
        unitDivisor = 1,
        defaultAmount = 64,
        step = 1,
        largeStep = 10,
        extraLargeStep = 64,
        min = 1
    },
    fluid = {
        title = "Craft Fluid",
        titleColor = colors.cyan,
        unitLabel = "B",
        unitDivisor = 1000,
        defaultAmount = 1000,
        step = 1000,
        largeStep = 10000,
        extraLargeStep = 100000,
        min = 1000
    },
    chemical = {
        title = "Craft Chemical",
        titleColor = colors.lightBlue,
        unitLabel = "B",
        unitDivisor = 1000,
        defaultAmount = 1000,
        step = 1000,
        largeStep = 10000,
        extraLargeStep = 100000,
        min = 1000
    }
}

-- Show craft dialog
-- @param monitor Monitor peripheral
-- @param peripheralName Name of monitor for touch filtering
-- @param opts Configuration:
--   preset: "item", "fluid", or "chemical" (uses PRESETS defaults)
--   title: Override title
--   titleColor: Override title bar color
--   resourceName: Display name of resource being crafted
--   resourceId: Registry name/ID for crafting
--   unitLabel: Unit suffix (e.g., "B" for buckets)
--   unitDivisor: Divide amount for display (1000 for mB->B)
--   defaultAmount: Starting amount
--   step/largeStep/extraLargeStep: Amount increments
--   min: Minimum amount
--   craftFunction: function(filter) to call for crafting
-- @return status table {success, message, amount} or nil if cancelled
function CraftDialog.show(monitor, peripheralName, opts)
    opts = opts or {}

    -- Apply preset defaults
    local preset = CraftDialog.PRESETS[opts.preset] or CraftDialog.PRESETS.item
    local config = {
        title = opts.title or preset.title,
        titleColor = opts.titleColor or preset.titleColor,
        resourceName = opts.resourceName or "Unknown",
        resourceId = opts.resourceId,
        unitLabel = opts.unitLabel or preset.unitLabel,
        unitDivisor = opts.unitDivisor or preset.unitDivisor,
        defaultAmount = opts.defaultAmount or preset.defaultAmount,
        step = opts.step or preset.step,
        largeStep = opts.largeStep or preset.largeStep,
        extraLargeStep = opts.extraLargeStep or preset.extraLargeStep,
        min = opts.min or preset.min,
        craftFunction = opts.craftFunction
    }

    local width, height = monitor.getSize()

    -- Calculate overlay bounds
    local overlayWidth = math.min(width - 2, 26)
    local overlayHeight = math.min(height - 2, 9)
    local x1 = math.floor((width - overlayWidth) / 2) + 1
    local y1 = math.floor((height - overlayHeight) / 2) + 1
    local x2 = x1 + overlayWidth - 1
    local y2 = y1 + overlayHeight - 1

    local craftAmount = config.defaultAmount
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
        monitor.setBackgroundColor(config.titleColor)
        monitor.setTextColor(colors.black)
        monitor.setCursorPos(x1, y1)
        monitor.write(string.rep(" ", overlayWidth))
        monitor.setCursorPos(x1 + 1, y1)
        monitor.write(Core.truncate(config.title, overlayWidth - 2))

        -- Content area
        monitor.setBackgroundColor(colors.gray)
        local contentY = y1 + 2

        -- Resource name
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.write(Core.truncate(config.resourceName, overlayWidth - 2))
        contentY = contentY + 1

        -- Amount display
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.setTextColor(colors.lightGray)
        monitor.write("Amount: ")
        monitor.setTextColor(colors.yellow)
        local displayAmount = craftAmount / config.unitDivisor
        if config.unitDivisor > 1 then
            monitor.write(tostring(displayAmount) .. config.unitLabel)
        else
            monitor.write(tostring(craftAmount))
        end
        contentY = contentY + 1

        -- Amount adjustment buttons
        local btnY = contentY
        local btnSpacing = 6
        local btn1X = x1 + 1
        local btn2X = btn1X + btnSpacing
        local btn3X = btn2X + btnSpacing

        monitor.setBackgroundColor(colors.lightGray)
        monitor.setTextColor(colors.black)

        -- Button labels based on unit
        local stepLabel, largeLabel, extraLabel
        if config.unitDivisor > 1 then
            stepLabel = "-1" .. config.unitLabel
            largeLabel = "+1" .. config.unitLabel
            extraLabel = "+10" .. config.unitLabel
        else
            stepLabel = "-10"
            largeLabel = "+10"
            extraLabel = "+64"
        end

        monitor.setCursorPos(btn1X, btnY)
        monitor.write(" " .. stepLabel .. " ")
        monitor.setCursorPos(btn2X, btnY)
        monitor.write(" " .. largeLabel .. " ")
        monitor.setCursorPos(btn3X, btnY)
        monitor.write(" " .. extraLabel .. " ")

        monitor.setBackgroundColor(colors.gray)
        contentY = contentY + 2

        -- Status message
        if statusMessage then
            monitor.setTextColor(statusColor)
            monitor.setCursorPos(x1 + 1, contentY)
            monitor.write(Core.truncate(statusMessage, overlayWidth - 2))
        end

        -- Action buttons
        local buttonY = y2 - 1

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

        if side == peripheralName then
            -- Close button or outside overlay
            if (ty == buttonY and tx >= x2 - 7 and tx <= x2 - 1) or
               tx < x1 or tx > x2 or ty < y1 or ty > y2 then
                return nil  -- Cancelled
            end

            -- Amount buttons
            if ty == btnY then
                if tx >= btn1X and tx < btn2X then
                    craftAmount = math.max(config.min, craftAmount - config.step)
                elseif tx >= btn2X and tx < btn3X then
                    craftAmount = craftAmount + config.step
                elseif tx >= btn3X and tx < btn3X + 6 then
                    craftAmount = craftAmount + config.largeStep
                end
            end

            -- Craft button
            if ty == buttonY and tx >= x1 + 2 and tx <= x1 + 8 then
                if config.craftFunction then
                    local filter = {
                        name = config.resourceId,
                        count = craftAmount
                    }

                    local ok, result = pcall(config.craftFunction, filter)

                    if ok and result then
                        local displayAmt = craftAmount / config.unitDivisor
                        if config.unitDivisor > 1 then
                            statusMessage = "Crafting " .. displayAmt .. config.unitLabel
                        else
                            statusMessage = "Crafting " .. craftAmount .. "x"
                        end
                        statusColor = colors.lime
                    elseif ok then
                        statusMessage = "Cannot craft"
                        statusColor = colors.orange
                    else
                        statusMessage = "Craft failed"
                        statusColor = colors.red
                    end
                else
                    statusMessage = "No craft function"
                    statusColor = colors.red
                end
            end
        end
    end
end

return CraftDialog
