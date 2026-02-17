-- ResourceDetailOverlay.lua
-- Resource detail overlay for ResourceBrowserFactory

local Text = mpm('utils/Text')
local Core = mpm('ui/Core')
local ModalOverlay = mpm('ui/ModalOverlay')

local ResourceDetailOverlay = {}

local function generateCraftLabels(amounts, unitDivisor, unitLabel)
    local labels = {}
    for _, amt in ipairs(amounts) do
        local displayAmt = amt / unitDivisor
        table.insert(labels, tostring(displayAmt) .. unitLabel)
    end
    return labels
end

function ResourceDetailOverlay.show(self, resource, config)
    local state = {
        craftAmount = config.craftAmounts[1],
        statusMessage = nil,
        statusColor = colors.gray,
        craftLabels = config.craftLabels or generateCraftLabels(config.craftAmounts, config.unitDivisor, config.unitLabel)
    }

    ModalOverlay.show(self, {
        maxWidth = 30,
        maxHeight = 10,
        title = resource.displayName or Text.prettifyName(resource[config.idField] or "Unknown"),
        titleBackgroundColor = config.titleColor,
        titleTextColor = colors.black,
        closeOnOutside = true,
        state = state,
        render = function(monitor, frame, state, addAction)
            local contentY = frame.y1 + 2
            local rawAmount = resource[config.amountField] or 0
            local displayAmount = rawAmount / config.unitDivisor
            local amountColor = config.highlightColor
            if displayAmount == 0 then
                amountColor = colors.red
            elseif displayAmount < config.lowThreshold then
                amountColor = colors.orange
            end

            monitor.setTextColor(colors.white)
            monitor.setCursorPos(frame.x1 + 1, contentY)
            monitor.write(config.amountLabel or "Stock: ")
            monitor.setTextColor(amountColor)
            local amountStr = Text.formatNumber(displayAmount, 0)
            if config.unitLabel ~= "" then amountStr = amountStr .. " " .. config.unitLabel end
            monitor.write(amountStr)
            contentY = contentY + 1

            local registryName = resource[config.idField]
            if registryName then
                monitor.setTextColor(colors.lightGray)
                monitor.setCursorPos(frame.x1 + 1, contentY)
                monitor.write(Core.truncate(registryName, frame.width - 2))
                contentY = contentY + 1
            end

            local isCraftable = resource.isCraftable or config.alwaysCraftable
            if isCraftable then
                contentY = contentY + 1
                monitor.setTextColor(colors.white)
                monitor.setCursorPos(frame.x1 + 1, contentY)
                monitor.write("Craft: ")

                local buttonX = frame.x1 + 8
                for i, amt in ipairs(config.craftAmounts) do
                    local label = state.craftLabels[i]
                    if amt == state.craftAmount then
                        monitor.setBackgroundColor(colors.cyan)
                        monitor.setTextColor(colors.black)
                    else
                        monitor.setBackgroundColor(colors.lightGray)
                        monitor.setTextColor(colors.gray)
                    end
                    monitor.setCursorPos(buttonX, contentY)
                    monitor.write(" " .. label .. " ")
                    addAction("amt:" .. i, buttonX, contentY, buttonX + #label + 1, contentY)
                    buttonX = buttonX + #label + 3
                end
                monitor.setBackgroundColor(colors.gray)
            end

            if state.statusMessage then
                monitor.setTextColor(state.statusColor)
                monitor.setCursorPos(frame.x1 + 1, frame.y2 - 2)
                monitor.write(Core.truncate(state.statusMessage, frame.width - 2))
            end

            local buttonY = frame.y2 - 1
            if isCraftable then
                local craftX = frame.x1 + 2
                monitor.setTextColor(colors.lime)
                monitor.setCursorPos(craftX, buttonY)
                monitor.write("[Craft]")
                addAction("craft", craftX, buttonY, craftX + 6, buttonY)
            end

            local closeX = frame.x2 - 7
            monitor.setTextColor(colors.red)
            monitor.setCursorPos(closeX, buttonY)
            monitor.write("[Close]")
            addAction("close", closeX, buttonY, closeX + 6, buttonY)
        end,
        onTouch = function(monitor, frame, state, tx, ty, action)
            if action == "close" then
                return true
            end

            if action and action:sub(1, 4) == "amt:" then
                local idx = tonumber(action:sub(5))
                if idx and config.craftAmounts[idx] then
                    state.craftAmount = config.craftAmounts[idx]
                end
                return false
            end

            if action == "craft" then
                local craftFn = config.getCraftFunction(self, resource)
                if craftFn then
                    local ok, result = pcall(function()
                        return craftFn({ name = resource[config.idField], count = state.craftAmount })
                    end)
                    if ok and result then
                        local displayCraftAmount = state.craftAmount / config.unitDivisor
                        state.statusMessage = "Crafting " .. displayCraftAmount .. config.unitLabel .. " started"
                        state.statusColor = colors.lime
                    else
                        state.statusMessage = "Craft failed"
                        state.statusColor = colors.red
                    end
                else
                    state.statusMessage = config.craftUnavailableMessage or "Crafting unavailable"
                    state.statusColor = colors.red
                end
            end

            return false
        end
    })
end

return ResourceDetailOverlay
