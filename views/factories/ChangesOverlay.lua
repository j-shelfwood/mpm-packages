-- ChangesOverlay.lua
-- Resource change detail overlay for ChangesFactory
-- Shows change details with baseline → current transition
-- Extracted from ChangesFactory.lua for maintainability

local Text = mpm('utils/Text')
local Core = mpm('ui/Core')

local ChangesOverlay = {}

-- Show resource detail overlay
-- @param self View instance (needs monitor, peripheralName)
-- @param resource Change data { id, change, current, baseline }
-- @param config Factory config { unitDivisor, unitLabel, accentColor }
function ChangesOverlay.show(self, resource, config)
    local monitor = self.monitor
    local width, height = monitor.getSize()

    local overlayWidth = math.min(width - 2, 28)
    local overlayHeight = math.min(height - 2, 8)
    local x1 = math.floor((width - overlayWidth) / 2) + 1
    local y1 = math.floor((height - overlayHeight) / 2) + 1
    local x2 = x1 + overlayWidth - 1
    local y2 = y1 + overlayHeight - 1

    local monitorName = self.peripheralName

    while true do
        -- Draw background
        monitor.setBackgroundColor(colors.gray)
        for y = y1, y2 do
            monitor.setCursorPos(x1, y)
            monitor.write(string.rep(" ", overlayWidth))
        end

        -- Title bar
        local titleColor = resource.change > 0 and colors.lime or colors.red
        monitor.setBackgroundColor(titleColor)
        monitor.setTextColor(colors.black)
        monitor.setCursorPos(x1, y1)
        monitor.write(string.rep(" ", overlayWidth))
        monitor.setCursorPos(x1 + 1, y1)
        local sign = resource.change > 0 and "+" or ""
        local displayChange = resource.change / config.unitDivisor
        monitor.write(Core.truncate(sign .. Text.formatNumber(displayChange, 1) .. config.unitLabel, overlayWidth - 2))

        -- Content
        monitor.setBackgroundColor(colors.gray)
        local contentY = y1 + 2

        -- Resource name
        local resourceName = Text.prettifyName(resource.id)
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.write(Core.truncate(resourceName, overlayWidth - 2))
        contentY = contentY + 1

        -- Registry name
        monitor.setTextColor(colors.lightGray)
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.write(Core.truncate(resource.id, overlayWidth - 2))
        contentY = contentY + 2

        -- Baseline → Current
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.write("Was: ")
        monitor.setTextColor(colors.yellow)
        monitor.write(Text.formatNumber(resource.baseline / config.unitDivisor, 1) .. config.unitLabel)
        monitor.setTextColor(colors.gray)
        monitor.write(" -> ")
        monitor.setTextColor(config.accentColor)
        monitor.write(Text.formatNumber(resource.current / config.unitDivisor, 1) .. config.unitLabel)

        -- Close button
        local buttonY = y2 - 1
        monitor.setBackgroundColor(colors.gray)
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(x1 + math.floor((overlayWidth - 7) / 2), buttonY)
        monitor.write("[Close]")

        Core.resetColors(monitor)

        local event, side, tx, ty = os.pullEvent("monitor_touch")

        if side == monitorName then
            return
        end
    end
end

return ChangesOverlay
