-- Button.lua
-- Touch button widget for monitors

local Button = {}
Button.__index = Button

-- Create a new button
-- @param monitor The monitor peripheral
-- @param x, y Position (top-left)
-- @param label Button text
-- @param handler Function to call on press
-- @return Button instance
function Button.new(monitor, x, y, label, handler)
    local self = setmetatable({}, Button)
    self.monitor = monitor
    self.x = x
    self.y = y
    self.label = label or ""
    self.handler = handler
    self.width = #self.label + 2  -- padding
    self.height = 1
    self.bgColor = colors.blue
    self.textColor = colors.white
    self.pressedColor = colors.lightBlue
    self.enabled = true

    return self
end

-- Set button colors
function Button:setColors(bg, text, pressed)
    self.bgColor = bg or self.bgColor
    self.textColor = text or self.textColor
    self.pressedColor = pressed or self.pressedColor
end

-- Enable/disable button
function Button:setEnabled(enabled)
    self.enabled = enabled
end

-- Update label
function Button:setLabel(label)
    self.label = label
    self.width = #label + 2
end

-- Render the button
-- @param pressed Whether to show pressed state
function Button:render(pressed)
    local bg = pressed and self.pressedColor or self.bgColor
    if not self.enabled then
        bg = colors.gray
    end

    self.monitor.setBackgroundColor(bg)
    self.monitor.setTextColor(self.enabled and self.textColor or colors.lightGray)

    self.monitor.setCursorPos(self.x, self.y)
    self.monitor.write(" " .. self.label .. " ")

    self.monitor.setBackgroundColor(colors.black)
    self.monitor.setTextColor(colors.white)
end

-- Check if coordinates are within button
function Button:contains(x, y)
    return x >= self.x and x < self.x + self.width and y == self.y
end

-- Handle touch event
-- @param x, y Touch coordinates
-- @return true if button was pressed
function Button:handleTouch(x, y)
    if not self.enabled then
        return false
    end

    if self:contains(x, y) then
        -- Visual feedback
        self:render(true)
        sleep(0.1)
        self:render(false)

        if self.handler then
            self.handler()
        end
        return true
    end

    return false
end

-- Get button bounds
function Button:getBounds()
    return self.x, self.y, self.x + self.width - 1, self.y + self.height - 1
end

return Button
