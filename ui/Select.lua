-- Select.lua
-- Option picker widget for monitors

local Select = {}
Select.__index = Select

-- Create a new select
-- @param monitor The monitor peripheral
-- @param x, y Position
-- @param label Label text
-- @param options Array of option strings or {value, label} tables
-- @param selectedIndex Initial selection (1-indexed)
-- @param onChange Function to call on change: onChange(value, index)
-- @return Select instance
function Select.new(monitor, x, y, label, options, selectedIndex, onChange)
    local self = setmetatable({}, Select)
    self.monitor = monitor
    self.x = x
    self.y = y
    self.label = label or ""
    self.options = options or {}
    self.selectedIndex = selectedIndex or 1
    self.onChange = onChange
    self.enabled = true
    self.maxDisplayWidth = 15  -- Max width for option display

    return self
end

-- Get normalized option (returns {value, label})
function Select:getOption(index)
    local opt = self.options[index]
    if type(opt) == "table" then
        return opt.value or opt[1], opt.label or opt[2] or opt[1]
    else
        return opt, tostring(opt)
    end
end

-- Get current value
function Select:getValue()
    local value, _ = self:getOption(self.selectedIndex)
    return value
end

-- Get current index
function Select:getIndex()
    return self.selectedIndex
end

-- Set by index
function Select:setIndex(index)
    if index >= 1 and index <= #self.options then
        self.selectedIndex = index
    end
end

-- Set by value
function Select:setValue(value)
    for i, opt in ipairs(self.options) do
        local v, _ = self:getOption(i)
        if v == value then
            self.selectedIndex = i
            return true
        end
    end
    return false
end

-- Enable/disable
function Select:setEnabled(enabled)
    self.enabled = enabled
end

-- Calculate layout
function Select:getLayout()
    local labelWidth = #self.label + 2
    local x = self.x + labelWidth

    return {
        prev = {x1 = x, x2 = x + 1},                    -- "<"
        value = {x1 = x + 2, x2 = x + 2 + self.maxDisplayWidth - 1},
        next = {x1 = x + 2 + self.maxDisplayWidth, x2 = x + 3 + self.maxDisplayWidth}  -- ">"
    }
end

-- Render the select
function Select:render()
    local textColor = self.enabled and colors.white or colors.gray
    local arrowColor = self.enabled and colors.yellow or colors.gray

    -- Label
    self.monitor.setBackgroundColor(colors.black)
    self.monitor.setTextColor(textColor)
    self.monitor.setCursorPos(self.x, self.y)
    self.monitor.write(self.label .. ": ")

    local layout = self:getLayout()

    -- Prev arrow
    self.monitor.setTextColor(arrowColor)
    self.monitor.write("< ")

    -- Current value
    local _, label = self:getOption(self.selectedIndex)
    label = label or "?"

    -- Truncate if needed
    if #label > self.maxDisplayWidth then
        label = label:sub(1, self.maxDisplayWidth - 3) .. "..."
    end

    -- Pad to fixed width
    local padding = self.maxDisplayWidth - #label
    local leftPad = math.floor(padding / 2)
    local rightPad = padding - leftPad

    self.monitor.setBackgroundColor(colors.gray)
    self.monitor.setTextColor(textColor)
    self.monitor.write(string.rep(" ", leftPad) .. label .. string.rep(" ", rightPad))

    -- Next arrow
    self.monitor.setBackgroundColor(colors.black)
    self.monitor.setTextColor(arrowColor)
    self.monitor.write(" >")

    self.monitor.setTextColor(colors.white)
end

-- Handle touch event
function Select:handleTouch(x, y)
    if not self.enabled or y ~= self.y or #self.options == 0 then
        return false
    end

    local layout = self:getLayout()
    local oldIndex = self.selectedIndex

    if x >= layout.prev.x1 and x <= layout.prev.x2 then
        -- Previous
        self.selectedIndex = self.selectedIndex - 1
        if self.selectedIndex < 1 then
            self.selectedIndex = #self.options
        end
    elseif x >= layout.next.x1 and x <= layout.next.x2 then
        -- Next
        self.selectedIndex = self.selectedIndex + 1
        if self.selectedIndex > #self.options then
            self.selectedIndex = 1
        end
    elseif x >= layout.value.x1 and x <= layout.value.x2 then
        -- Tap on value = next
        self.selectedIndex = self.selectedIndex + 1
        if self.selectedIndex > #self.options then
            self.selectedIndex = 1
        end
    end

    if self.selectedIndex ~= oldIndex then
        self:render()

        if self.onChange then
            local value, _ = self:getOption(self.selectedIndex)
            self.onChange(value, self.selectedIndex)
        end
        return true
    end

    return false
end

return Select
