-- List.lua
-- Scrollable list picker for monitors
-- Extracted from ConfigUI.drawPicker for reuse

local Core = mpm('ui/Core')

local List = {}
List.__index = List

-- Create a new list picker
-- @param monitor Monitor peripheral
-- @param options Array of options (strings or tables with value/label/name)
-- @param opts Configuration table:
--   title: Header text (default: "Select")
--   selected: Currently selected value
--   formatFn: Function to format option for display (receives option)
--   cancelText: Cancel button text (default: "Cancel")
--   showCancel: Whether to show cancel button (default: true)
-- @return List instance
function List.new(monitor, options, opts)
    local self = setmetatable({}, List)

    self.monitor = monitor
    self.options = options or {}
    opts = opts or {}

    self.title = opts.title or "Select"
    self.selected = opts.selected
    self.cancelText = opts.cancelText or "Cancel"
    self.showCancel = opts.showCancel ~= false

    self.formatFn = opts.formatFn or function(opt)
        if type(opt) == "table" then
            return opt.label or opt.name or tostring(opt.value or opt)
        end
        return tostring(opt)
    end

    self.scrollOffset = 0
    self.width, self.height = monitor.getSize()

    return self
end

-- Get value from an option
local function getValue(opt)
    if type(opt) == "table" then
        return opt.value or opt.name or opt
    end
    return opt
end

-- Find index of currently selected value
function List:findSelectedIndex()
    for i, opt in ipairs(self.options) do
        if getValue(opt) == self.selected then
            return i
        end
    end
    return 1
end

-- Calculate visible area
function List:getLayout()
    local titleHeight = 1
    local spacing = 1
    local cancelHeight = self.showCancel and 1 or 0
    local padding = 1

    local startY = titleHeight + spacing + 1
    local maxVisible = self.height - startY - cancelHeight - padding + 1

    return {
        titleY = 1,
        startY = startY,
        maxVisible = math.max(1, maxVisible),
        cancelY = self.height
    }
end

-- Render the list
function List:render()
    local layout = self:getLayout()

    Core.clear(self.monitor)

    -- Title bar
    Core.drawBar(self.monitor, layout.titleY, self.title, Core.COLORS.titleBar, Core.COLORS.titleText)

    -- Options list
    local visibleCount = math.min(layout.maxVisible, #self.options - self.scrollOffset)

    for i = 1, visibleCount do
        local optIndex = i + self.scrollOffset
        local opt = self.options[optIndex]

        if opt then
            local y = layout.startY + i - 1
            local label = self.formatFn(opt)
            local value = getValue(opt)
            local isSelected = value == self.selected

            -- Truncate if too long
            label = Core.truncate(label, self.width - 4)

            if isSelected then
                -- Highlighted row
                self.monitor.setBackgroundColor(Core.COLORS.selection)
                self.monitor.setTextColor(Core.COLORS.selectionText)
                self.monitor.setCursorPos(1, y)
                self.monitor.write(string.rep(" ", self.width))
                self.monitor.setCursorPos(2, y)
                self.monitor.write("> " .. label)
            else
                -- Normal row
                self.monitor.setBackgroundColor(Core.COLORS.background)
                self.monitor.setTextColor(Core.COLORS.textMuted)
                self.monitor.setCursorPos(2, y)
                self.monitor.write("  " .. label)
            end
        end
    end

    -- Scroll indicators
    self.monitor.setBackgroundColor(Core.COLORS.background)
    self.monitor.setTextColor(Core.COLORS.textMuted)

    if self.scrollOffset > 0 then
        self.monitor.setCursorPos(self.width, layout.startY)
        self.monitor.write("^")
    end

    if self.scrollOffset + layout.maxVisible < #self.options then
        self.monitor.setCursorPos(self.width, layout.startY + layout.maxVisible - 1)
        self.monitor.write("v")
    end

    -- Cancel button
    if self.showCancel then
        Core.drawBar(self.monitor, layout.cancelY, self.cancelText, Core.COLORS.cancelButton, Core.COLORS.titleText)
    end

    Core.resetColors(self.monitor)
end

-- Handle touch event
-- @return "scroll_up", "scroll_down", "cancel", selected value, or nil
function List:handleTouch(x, y)
    local layout = self:getLayout()

    -- Cancel button
    if self.showCancel and y == layout.cancelY then
        return "cancel"
    end

    -- Scroll up indicator
    if y == layout.startY and x == self.width and self.scrollOffset > 0 then
        return "scroll_up"
    end

    -- Scroll down indicator
    if y == layout.startY + layout.maxVisible - 1 and x == self.width then
        if self.scrollOffset + layout.maxVisible < #self.options then
            return "scroll_down"
        end
    end

    -- Option selection
    if y >= layout.startY and y < layout.startY + layout.maxVisible then
        local optIndex = (y - layout.startY + 1) + self.scrollOffset
        if optIndex >= 1 and optIndex <= #self.options then
            return getValue(self.options[optIndex])
        end
    end

    return nil
end

-- Show the list and wait for selection
-- @return Selected value or nil if cancelled
function List:show()
    -- Scroll to show current selection
    local selectedIndex = self:findSelectedIndex()
    local layout = self:getLayout()

    if selectedIndex > layout.maxVisible then
        self.scrollOffset = selectedIndex - layout.maxVisible
    end

    local monitorName = peripheral.getName(self.monitor)

    while true do
        self:render()

        local event, side, x, y = os.pullEvent("monitor_touch")

        if side == monitorName then
            local result = self:handleTouch(x, y)

            if result == "cancel" then
                return nil
            elseif result == "scroll_up" then
                self.scrollOffset = math.max(0, self.scrollOffset - 1)
            elseif result == "scroll_down" then
                self.scrollOffset = self.scrollOffset + 1
            elseif result ~= nil then
                return result
            end
        end
    end
end

return List
