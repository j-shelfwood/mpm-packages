-- ChangesOverlay.lua
-- Resource change detail overlay for ChangesFactory

local Text = mpm('utils/Text')
local Core = mpm('ui/Core')
local ModalOverlay = mpm('ui/ModalOverlay')

local ChangesOverlay = {}

function ChangesOverlay.show(self, resource, config)
    local titleColor = resource.change > 0 and colors.lime or colors.red
    local sign = resource.change > 0 and "+" or ""
    local displayChange = resource.change / config.unitDivisor

    ModalOverlay.show(self, {
        maxWidth = 28,
        maxHeight = 8,
        title = sign .. Text.formatNumber(displayChange, 1) .. config.unitLabel,
        titleBackgroundColor = titleColor,
        titleTextColor = colors.black,
        closeOnOutside = true,
        render = function(monitor, frame, state, addAction)
            local contentY = frame.y1 + 2

            monitor.setTextColor(colors.white)
            monitor.setCursorPos(frame.x1 + 1, contentY)
            monitor.write(Core.truncate(Text.prettifyName(resource.id), frame.width - 2))
            contentY = contentY + 1

            monitor.setTextColor(colors.lightGray)
            monitor.setCursorPos(frame.x1 + 1, contentY)
            monitor.write(Core.truncate(resource.id, frame.width - 2))
            contentY = contentY + 2

            monitor.setTextColor(colors.white)
            monitor.setCursorPos(frame.x1 + 1, contentY)
            monitor.write("Was: ")
            monitor.setTextColor(colors.yellow)
            monitor.write(Text.formatNumber(resource.baseline / config.unitDivisor, 1) .. config.unitLabel)
            monitor.setTextColor(colors.gray)
            monitor.write(" -> ")
            monitor.setTextColor(config.accentColor)
            monitor.write(Text.formatNumber(resource.current / config.unitDivisor, 1) .. config.unitLabel)

            local closeLabel = "[Close]"
            local closeX = frame.x1 + math.floor((frame.width - #closeLabel) / 2)
            local closeY = frame.y2 - 1
            monitor.setTextColor(colors.white)
            monitor.setCursorPos(closeX, closeY)
            monitor.write(closeLabel)
            addAction("close", closeX, closeY, closeX + #closeLabel - 1, closeY)
        end,
        onTouch = function(monitor, frame, state, tx, ty, action)
            if action == "close" then
                return true
            end
            return false
        end
    })
end

return ChangesOverlay
