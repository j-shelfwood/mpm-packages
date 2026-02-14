-- Mock Monitor Peripheral
-- Simulates CC:Tweaked monitor for view testing

local Monitor = {}
Monitor.__index = Monitor

function Monitor.new(config)
    config = config or {}
    local self = setmetatable({}, Monitor)

    self.width = config.width or 51
    self.height = config.height or 19
    self.text_scale = config.textScale or 1
    self.cursor_x = 1
    self.cursor_y = 1
    self.bg_color = colors and colors.black or 1
    self.text_color = colors and colors.white or 2
    self.cursor_blink = false

    -- Buffer for rendered content
    self.buffer = {}
    self.color_buffer = {}
    for y = 1, self.height do
        self.buffer[y] = string.rep(" ", self.width)
        self.color_buffer[y] = {
            text = string.rep("0", self.width),
            bg = string.rep("f", self.width)
        }
    end

    -- Log of operations for testing
    self.operations = {}

    return self
end

-- Size operations
function Monitor:getSize()
    return self.width, self.height
end

function Monitor:setTextScale(scale)
    self.text_scale = scale
    table.insert(self.operations, {op = "setTextScale", scale = scale})
end

function Monitor:getTextScale()
    return self.text_scale
end

-- Cursor operations
function Monitor:getCursorPos()
    return self.cursor_x, self.cursor_y
end

function Monitor:setCursorPos(x, y)
    self.cursor_x = math.floor(x)
    self.cursor_y = math.floor(y)
end

function Monitor:setCursorBlink(blink)
    self.cursor_blink = blink
end

function Monitor:getCursorBlink()
    return self.cursor_blink
end

-- Color operations
function Monitor:setTextColor(color)
    self.text_color = color
end

function Monitor:setTextColour(color)
    self.text_color = color
end

function Monitor:getTextColor()
    return self.text_color
end

function Monitor:getTextColour()
    return self.text_color
end

function Monitor:setBackgroundColor(color)
    self.bg_color = color
end

function Monitor:setBackgroundColour(color)
    self.bg_color = color
end

function Monitor:getBackgroundColor()
    return self.bg_color
end

function Monitor:getBackgroundColour()
    return self.bg_color
end

function Monitor:isColor()
    return true
end

function Monitor:isColour()
    return true
end

function Monitor:getPaletteColor(color)
    return 0, 0, 0
end

function Monitor:getPaletteColour(color)
    return 0, 0, 0
end

function Monitor:setPaletteColor(color, r, g, b)
    -- No-op
end

function Monitor:setPaletteColour(color, r, g, b)
    -- No-op
end

-- Writing operations
function Monitor:write(text)
    text = tostring(text)
    local y = self.cursor_y
    if y >= 1 and y <= self.height then
        local line = self.buffer[y]
        local x = self.cursor_x
        for i = 1, #text do
            if x >= 1 and x <= self.width then
                local before = line:sub(1, x - 1)
                local after = line:sub(x + 1)
                line = before .. text:sub(i, i) .. after
            end
            x = x + 1
        end
        self.buffer[y] = line
        self.cursor_x = self.cursor_x + #text
    end
    table.insert(self.operations, {op = "write", text = text, x = self.cursor_x - #text, y = y})
end

function Monitor:blit(text, text_colors, bg_colors)
    self:write(text)
end

function Monitor:clear()
    for y = 1, self.height do
        self.buffer[y] = string.rep(" ", self.width)
    end
    table.insert(self.operations, {op = "clear"})
end

function Monitor:clearLine()
    local y = self.cursor_y
    if y >= 1 and y <= self.height then
        self.buffer[y] = string.rep(" ", self.width)
    end
end

function Monitor:scroll(lines)
    if lines > 0 then
        for y = 1, self.height - lines do
            self.buffer[y] = self.buffer[y + lines]
        end
        for y = self.height - lines + 1, self.height do
            self.buffer[y] = string.rep(" ", self.width)
        end
    elseif lines < 0 then
        for y = self.height, 1 - lines, -1 do
            self.buffer[y] = self.buffer[y + lines]
        end
        for y = 1, -lines do
            self.buffer[y] = string.rep(" ", self.width)
        end
    end
end

-- Test helpers
function Monitor:getLine(y)
    return self.buffer[y]
end

function Monitor:getBuffer()
    return self.buffer
end

function Monitor:getOperations()
    return self.operations
end

function Monitor:clearOperations()
    self.operations = {}
end

function Monitor:dump()
    local lines = {}
    for y = 1, self.height do
        table.insert(lines, string.format("%2d: |%s|", y, self.buffer[y]))
    end
    return table.concat(lines, "\n")
end

function Monitor:findText(pattern)
    for y = 1, self.height do
        local x = self.buffer[y]:find(pattern)
        if x then
            return x, y
        end
    end
    return nil
end

return Monitor
