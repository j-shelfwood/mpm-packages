-- Toggle.lua
-- Boolean toggle widget for monitors

local Toggle = {}
Toggle.__index = Toggle

-- Create a new toggle
-- @param monitor The monitor peripheral
-- @param x, y Position
-- @param label Label text
-- @param value Initial value (boolean)
-- @param onChange Function to call on change: onChange(newValue)
-- @return Toggle instance
function Toggle.new(monitor, x, y, label, value, onChange)
    local self = setmetatable({}, Toggle)
    self.monitor = monitor
    self.x = x
    self.y = y
    self.label = label or ""
    self.value = value or false
    self.onChange = onChange
    self.onColor = colors.green
    self.offColor = colors.red
    self.labelColor = colors.white
    self.enabled = true

    return self
end

-- Set colors
function Toggle:setColors(onColor, offColor, labelColor)
    self.onColor = onColor or self.onColor
    self.offColor = offColor or self.offColor
    self.labelColor = labelColor or self.labelColor
end

-- Get/set value
function Toggle:getValue()
    return self.value
end

function Toggle:setValue(value)
    self.value = value
end

-- Enable/disable
function Toggle:setEnabled(enabled)
    self.enabled = enabled
end

-- Calculate total width
function Toggle:getWidth()
    -- Format: "Label: [YES] NO" or "Label: YES [NO]"
    return #self.label + 2 + 5 + 1 + 4  -- label + ": " + "[YES]" + " " + "NO"
end

-- Render the toggle
function Toggle:render()
    local yesText = self.value and "[YES]" or " YES "
    local noText = self.value and "  NO " or "[ NO]"

    -- Label
    self.monitor.setBackgroundColor(colors.black)
    self.monitor.setTextColor(self.enabled and self.labelColor or colors.gray)
    self.monitor.setCursorPos(self.x, self.y)
    self.monitor.write(self.label .. ": ")

    -- YES button
    if self.value then
        self.monitor.setBackgroundColor(self.onColor)
        self.monitor.setTextColor(colors.white)
    else
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(self.enabled and colors.lightGray or colors.gray)
    end
    self.monitor.write(yesText)

    -- Separator
    self.monitor.setBackgroundColor(colors.black)
    self.monitor.write(" ")

    -- NO button
    if not self.value then
        self.monitor.setBackgroundColor(self.offColor)
        self.monitor.setTextColor(colors.white)
    else
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(self.enabled and colors.lightGray or colors.gray)
    end
    self.monitor.write(noText)

    self.monitor.setBackgroundColor(colors.black)
    self.monitor.setTextColor(colors.white)
end

-- Get touch zones for YES and NO
function Toggle:getZones()
    local labelWidth = #self.label + 2
    local yesX = self.x + labelWidth
    local noX = yesX + 6

    return {
        yes = {x1 = yesX, x2 = yesX + 4, y = self.y},
        no = {x1 = noX, x2 = noX + 4, y = self.y}
    }
end

-- Handle touch event
function Toggle:handleTouch(x, y)
    if not self.enabled then
        return false
    end

    local zones = self:getZones()

    if y == self.y then
        local newValue = nil

        if x >= zones.yes.x1 and x <= zones.yes.x2 then
            newValue = true
        elseif x >= zones.no.x1 and x <= zones.no.x2 then
            newValue = false
        end

        if newValue ~= nil and newValue ~= self.value then
            self.value = newValue
            self:render()

            if self.onChange then
                self.onChange(self.value)
            end
            return true
        end
    end

    return false
end

return Toggle
