-- Dialog.lua
-- Input dialog framework for monitors
-- Provides modal dialogs with configurable widgets

local Core = mpm('ui/Core')
local ModalOverlay = mpm('ui/ModalOverlay')
local Button = mpm('ui/Button')

local Dialog = {}
Dialog.__index = Dialog

-- Create a new dialog
-- @param monitor The monitor peripheral
-- @return Dialog instance
function Dialog.new(monitor)
    local self = setmetatable({}, Dialog)
    self.monitor = monitor
    self.title = ""
    self.widgets = {}
    self.result = nil
    self.cancelled = false
    self.running = false

    return self
end

-- Set dialog title
function Dialog:setTitle(title)
    self.title = title or ""
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
    -- Retained for API compatibility. Rendering is coordinated by show().
end

local function renderWithFrame(self, monitor, frame)
    local contentX = frame.x1 + 1
    local contentY = frame.y1 + 2
    local buttonY = frame.y2 - 1

    for i, widget in ipairs(self.widgets) do
        widget.x = contentX
        widget.y = contentY + i - 1
        widget:render()
    end

    self.okButton = Button.confirm(monitor, frame.x1 + 1, buttonY, "OK", function()
        self.result = self:collectValues()
        self.running = false
    end)

    self.cancelButton = Button.cancel(monitor, frame.x2 - 8, buttonY, "Cancel", function()
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

    local _, monitorHeight = self.monitor.getSize()
    local result = ModalOverlay.show(self.monitor, {
        title = self.title,
        closeOnOutside = false,
        height = math.min(monitorHeight - 2, math.max(6, #self.widgets + 4)),
        render = function(monitor, frame)
            renderWithFrame(self, monitor, frame)
        end,
        onTouch = function(_, _, _, x, y)
            self:handleTouch(x, y)
            if self.running then
                return false, nil
            end
            if self.cancelled then
                return true, nil
            end
            return true, self.result
        end
    })

    return result
end

-- Show a simple confirmation dialog
-- @param monitor Monitor peripheral
-- @param title Dialog title
-- @param message Message to display
-- @return true if confirmed, false if cancelled
function Dialog.confirm(monitor, title, message)
    local _, height = monitor.getSize()
    local state = {}

    return ModalOverlay.show(monitor, {
        title = title,
        closeOnOutside = false,
        height = math.min(height - 2, 7),
        render = function(m, frame)
            local text = Core.truncate(message, frame.width - 2)
            local textX = frame.x1 + math.floor((frame.width - #text) / 2)
            local textY = frame.y1 + 2
            m.setBackgroundColor(colors.gray)
            m.setTextColor(Core.COLORS.text)
            m.setCursorPos(textX, textY)
            m.write(text)

            local buttonY = frame.y2 - 1
            state.okButton = Button.confirm(m, frame.x1 + 1, buttonY, "OK")
            state.cancelButton = Button.cancel(m, frame.x2 - 8, buttonY, "Cancel")
            state.okButton:render()
            state.cancelButton:render()
        end,
        onTouch = function(_, _, _, x, y)
            if state.okButton and state.okButton:handleTouch(x, y) then
                return true, true
            end
            if state.cancelButton and state.cancelButton:handleTouch(x, y) then
                return true, false
            end
            return false, nil
        end
    })
end

return Dialog
