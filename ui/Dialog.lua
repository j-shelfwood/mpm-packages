-- Dialog.lua
-- Input dialog framework for monitors
-- Provides modal dialogs with configurable widgets

local Core = mpm('ui/Core')
local Overlay = mpm('ui/Overlay')
local Button = mpm('ui/Button')

local Dialog = {}
Dialog.__index = Dialog

-- Create a new dialog
-- @param monitor The monitor peripheral
-- @return Dialog instance
function Dialog.new(monitor)
    local self = setmetatable({}, Dialog)
    self.monitor = monitor
    self.overlay = Overlay.new(monitor, {footerHeight = 1})
    self.widgets = {}
    self.result = nil
    self.cancelled = false
    self.running = false

    return self
end

-- Set dialog title
function Dialog:setTitle(title)
    self.overlay.title = title
end

-- Add a widget to the dialog
-- @param widget Any widget with render() and handleTouch() methods
function Dialog:addWidget(widget)
    table.insert(self.widgets, widget)
end

-- Clear all widgets
function Dialog:clearWidgets()
    self.widgets = {}
end

-- Render the dialog
function Dialog:render()
    -- Build content lines from widget count (for sizing)
    local contentLines = {}
    for i = 1, #self.widgets + 2 do  -- +2 for spacing and buttons
        table.insert(contentLines, "")
    end

    self.overlay.content = contentLines
    self.overlay:render()

    -- Render widgets
    local cx1, cy1, cx2, cy2 = self.overlay:getContentBounds()

    for i, widget in ipairs(self.widgets) do
        -- Position widget within content area
        widget.x = cx1
        widget.y = cy1 + i - 1
        widget:render()
    end

    -- Render OK/Cancel buttons in footer area
    local fx1, fy1, fx2, fy2 = self.overlay:getFooterBounds()
    local buttonY = fy1

    self.okButton = Button.confirm(self.monitor, fx1, buttonY, "OK", function()
        self.result = self:collectValues()
        self.running = false
    end)

    self.cancelButton = Button.cancel(self.monitor, fx2 - 8, buttonY, "Cancel", function()
        self.cancelled = true
        self.running = false
    end)

    self.okButton:render()
    self.cancelButton:render()
end

-- Collect values from all widgets
function Dialog:collectValues()
    local values = {}
    for i, widget in ipairs(self.widgets) do
        if widget.getValue then
            values[i] = widget:getValue()
        end
    end
    return values
end

-- Handle touch event
function Dialog:handleTouch(x, y)
    -- Check buttons first
    if self.okButton and self.okButton:handleTouch(x, y) then
        return true
    end

    if self.cancelButton and self.cancelButton:handleTouch(x, y) then
        return true
    end

    -- Check widgets
    for _, widget in ipairs(self.widgets) do
        if widget.handleTouch and widget:handleTouch(x, y) then
            return true
        end
    end

    return false
end

-- Show dialog and wait for result
-- @return result table or nil if cancelled
function Dialog:show()
    self.running = true
    self.cancelled = false
    self.result = nil

    self:render()

    local monitorName = peripheral.getName(self.monitor)

    while self.running do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "monitor_touch" and p1 == monitorName then
            self:handleTouch(p2, p3)
        end
    end

    self.overlay:hide()

    if self.cancelled then
        return nil
    end

    return self.result
end

-- Show a simple confirmation dialog
-- @param monitor Monitor peripheral
-- @param title Dialog title
-- @param message Message to display
-- @return true if confirmed, false if cancelled
function Dialog.confirm(monitor, title, message)
    local width, height = monitor.getSize()

    Core.clear(monitor)

    -- Title bar
    Core.drawBar(monitor, 1, title, Core.COLORS.titleBar, Core.COLORS.titleText)

    -- Message (centered)
    local msgY = math.floor(height / 2)
    monitor.setTextColor(Core.COLORS.text)
    local msgX = Core.centerX(width, #message)
    monitor.setCursorPos(msgX, msgY)
    monitor.write(message)

    -- Buttons
    local buttonY = msgY + 2
    local result = nil

    local okButton = Button.confirm(monitor, math.floor(width / 2) - 6, buttonY, "OK", function()
        result = true
    end)

    local cancelButton = Button.cancel(monitor, math.floor(width / 2) + 2, buttonY, "Cancel", function()
        result = false
    end)

    okButton:render()
    cancelButton:render()

    local monitorName = peripheral.getName(monitor)

    while result == nil do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "monitor_touch" and p1 == monitorName then
            okButton:handleTouch(p2, p3)
            cancelButton:handleTouch(p2, p3)
        end
    end

    return result
end

return Dialog
