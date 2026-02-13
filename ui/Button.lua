-- Button.lua
-- Touch button widget for monitors
-- Enhanced with configurable padding and min-width

local Core = mpm('ui/Core')
local EventUtils = mpm('utils/EventUtils')

local Button = {}
Button.__index = Button

-- Create a new button
-- @param monitor The monitor peripheral
-- @param x, y Position (top-left)
-- @param label Button text
-- @param handler Function to call on press (optional)
-- @param opts Configuration table:
--   padding: Inner padding on each side (default: Core.BUTTON_PADDING)
--   minWidth: Minimum button width
-- @return Button instance
function Button.new(monitor, x, y, label, handler, opts)
    local self = setmetatable({}, Button)

    opts = opts or {}

    self.monitor = monitor
    self.x = x
    self.y = y
    self.label = label or ""
    self.handler = handler
    self.padding = opts.padding or Core.BUTTON_PADDING
    self.minWidth = opts.minWidth or 0
    self.height = 1
    self.enabled = true

    -- Colors
    self.bgColor = Core.COLORS.neutralButton
    self.textColor = colors.white
    self.pressedColor = colors.lightBlue
    self.disabledBgColor = Core.COLORS.disabledButton
    self.disabledTextColor = colors.lightGray

    self:updateWidth()

    return self
end

-- Recalculate width based on label and padding
function Button:updateWidth()
    local contentWidth = #self.label + (self.padding * 2)
    self.width = math.max(contentWidth, self.minWidth)
end

-- Set button colors
-- @param bg Background color
-- @param text Text color
-- @param pressed Pressed state color
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
    self.label = label or ""
    self:updateWidth()
end

-- Update position
function Button:setPosition(x, y)
    self.x = x
    self.y = y
end

-- Render the button
-- @param pressed Whether to show pressed state
function Button:render(pressed)
    local bg, fg

    if not self.enabled then
        bg = self.disabledBgColor
        fg = self.disabledTextColor
    elseif pressed then
        bg = self.pressedColor
        fg = self.textColor
    else
        bg = self.bgColor
        fg = self.textColor
    end

    self.monitor.setBackgroundColor(bg)
    self.monitor.setTextColor(fg)

    -- Build padded label
    local paddedLabel = Core.padText(self.label, self.width - (self.padding * 2), "center")
    local paddingStr = string.rep(" ", self.padding)
    local buttonText = paddingStr .. paddedLabel .. paddingStr

    -- Ensure exact width
    buttonText = buttonText:sub(1, self.width)
    if #buttonText < self.width then
        buttonText = buttonText .. string.rep(" ", self.width - #buttonText)
    end

    self.monitor.setCursorPos(self.x, self.y)
    self.monitor.write(buttonText)

    Core.resetColors(self.monitor)
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
        -- Visual feedback (using safe sleep to preserve events for other monitors)
        self:render(true)
        EventUtils.sleep(0.1)
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
    return {
        x1 = self.x,
        y1 = self.y,
        x2 = self.x + self.width - 1,
        y2 = self.y + self.height - 1
    }
end

-- Static helper: Create a confirm button (green)
function Button.confirm(monitor, x, y, label, handler, opts)
    local btn = Button.new(monitor, x, y, label or "OK", handler, opts)
    btn:setColors(Core.COLORS.confirmButton, colors.white, colors.lime)
    return btn
end

-- Static helper: Create a cancel button (red)
function Button.cancel(monitor, x, y, label, handler, opts)
    local btn = Button.new(monitor, x, y, label or "Cancel", handler, opts)
    btn:setColors(Core.COLORS.cancelButton, colors.white, colors.pink)
    return btn
end

-- Static helper: Create a neutral button (blue)
function Button.neutral(monitor, x, y, label, handler, opts)
    local btn = Button.new(monitor, x, y, label, handler, opts)
    btn:setColors(colors.blue, colors.white, colors.lightBlue)
    return btn
end

return Button
