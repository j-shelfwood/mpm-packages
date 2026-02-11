-- Stepper.lua
-- Number increment/decrement widget for monitors

local Stepper = {}
Stepper.__index = Stepper

-- Create a new stepper
-- @param monitor The monitor peripheral
-- @param x, y Position
-- @param label Label text
-- @param value Initial value
-- @param options Table with: min, max, step, largeStep
-- @param onChange Function to call on change: onChange(newValue)
-- @return Stepper instance
function Stepper.new(monitor, x, y, label, value, options, onChange)
    options = options or {}

    local self = setmetatable({}, Stepper)
    self.monitor = monitor
    self.x = x
    self.y = y
    self.label = label or ""
    self.value = value or 0
    self.min = options.min or 0
    self.max = options.max or 999999
    self.step = options.step or 1
    self.largeStep = options.largeStep or 10
    self.onChange = onChange
    self.valueWidth = options.valueWidth or 6  -- Display width for value
    self.enabled = true

    return self
end

-- Get/set value
function Stepper:getValue()
    return self.value
end

function Stepper:setValue(value)
    self.value = math.max(self.min, math.min(self.max, value))
end

-- Enable/disable
function Stepper:setEnabled(enabled)
    self.enabled = enabled
end

-- Calculate layout positions
function Stepper:getLayout()
    local labelWidth = #self.label + 2  -- "Label: "
    local x = self.x + labelWidth

    return {
        largeDown = {x1 = x, x2 = x + 2},       -- "[-]"
        smallDown = {x1 = x + 3, x2 = x + 4},   -- "[-"
        value = {x1 = x + 5, x2 = x + 5 + self.valueWidth - 1},
        smallUp = {x1 = x + 5 + self.valueWidth, x2 = x + 6 + self.valueWidth},  -- "+]"
        largeUp = {x1 = x + 7 + self.valueWidth, x2 = x + 9 + self.valueWidth}   -- "[+]"
    }
end

-- Render the stepper
function Stepper:render()
    local textColor = self.enabled and colors.white or colors.gray
    local buttonBg = self.enabled and colors.gray or colors.black
    local valueBg = colors.black

    -- Label
    self.monitor.setBackgroundColor(colors.black)
    self.monitor.setTextColor(textColor)
    self.monitor.setCursorPos(self.x, self.y)
    self.monitor.write(self.label .. ": ")

    local layout = self:getLayout()

    -- Large down button
    self.monitor.setBackgroundColor(buttonBg)
    self.monitor.setTextColor(self.enabled and colors.red or colors.gray)
    self.monitor.write("[-]")

    -- Small down button
    self.monitor.setTextColor(self.enabled and colors.orange or colors.gray)
    self.monitor.write("<")

    -- Value display
    self.monitor.setBackgroundColor(valueBg)
    self.monitor.setTextColor(textColor)
    local valueStr = tostring(self.value)
    local padding = self.valueWidth - #valueStr
    local leftPad = math.floor(padding / 2)
    local rightPad = padding - leftPad
    self.monitor.write(string.rep(" ", leftPad) .. valueStr .. string.rep(" ", rightPad))

    -- Small up button
    self.monitor.setBackgroundColor(buttonBg)
    self.monitor.setTextColor(self.enabled and colors.lime or colors.gray)
    self.monitor.write(">")

    -- Large up button
    self.monitor.setTextColor(self.enabled and colors.green or colors.gray)
    self.monitor.write("[+]")

    self.monitor.setBackgroundColor(colors.black)
    self.monitor.setTextColor(colors.white)
end

-- Handle touch event
function Stepper:handleTouch(x, y)
    if not self.enabled or y ~= self.y then
        return false
    end

    local layout = self:getLayout()
    local oldValue = self.value
    local newValue = self.value

    if x >= layout.largeDown.x1 and x <= layout.largeDown.x2 then
        newValue = self.value - self.largeStep
    elseif x >= layout.smallDown.x1 and x <= layout.smallDown.x2 then
        newValue = self.value - self.step
    elseif x >= layout.smallUp.x1 and x <= layout.smallUp.x2 then
        newValue = self.value + self.step
    elseif x >= layout.largeUp.x1 and x <= layout.largeUp.x2 then
        newValue = self.value + self.largeStep
    end

    newValue = math.max(self.min, math.min(self.max, newValue))

    if newValue ~= oldValue then
        self.value = newValue
        self:render()

        if self.onChange then
            self.onChange(self.value)
        end
        return true
    end

    return false
end

return Stepper
