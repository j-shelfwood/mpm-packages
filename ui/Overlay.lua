-- Overlay.lua
-- Modal overlay rendering for monitors
-- Provides a semi-modal UI layer on top of existing content

local Overlay = {}
Overlay.__index = Overlay

-- Create a new overlay for a monitor
-- @param monitor The monitor peripheral
-- @return Overlay instance
function Overlay.new(monitor)
    if not monitor then
        error("Overlay requires a monitor peripheral")
    end

    local self = setmetatable({}, Overlay)
    self.monitor = monitor
    self.width, self.height = monitor.getSize()
    self.visible = false
    self.title = ""
    self.content = {}
    self.backgroundColor = colors.gray
    self.borderColor = colors.lightGray
    self.titleColor = colors.white
    self.textColor = colors.white

    return self
end

-- Update dimensions (call after text scale changes)
function Overlay:updateDimensions()
    self.width, self.height = self.monitor.getSize()
end

-- Set overlay colors
function Overlay:setColors(bg, border, title, text)
    self.backgroundColor = bg or self.backgroundColor
    self.borderColor = border or self.borderColor
    self.titleColor = title or self.titleColor
    self.textColor = text or self.textColor
end

-- Calculate overlay bounds (centered, with padding)
-- @param contentHeight Number of content lines
-- @param contentWidth Desired content width (nil = auto)
-- @return x1, y1, x2, y2 (overlay bounds)
function Overlay:calculateBounds(contentHeight, contentWidth)
    contentWidth = contentWidth or math.floor(self.width * 0.8)
    local totalHeight = contentHeight + 4  -- title + border + padding

    local x1 = math.floor((self.width - contentWidth) / 2)
    local y1 = math.floor((self.height - totalHeight) / 2)
    local x2 = x1 + contentWidth - 1
    local y2 = y1 + totalHeight - 1

    -- Clamp to screen
    x1 = math.max(1, x1)
    y1 = math.max(1, y1)
    x2 = math.min(self.width, x2)
    y2 = math.min(self.height, y2)

    return x1, y1, x2, y2
end

-- Draw the overlay background and border
-- @param x1, y1, x2, y2 Bounds
function Overlay:drawFrame(x1, y1, x2, y2)
    local width = x2 - x1 + 1

    -- Fill background
    self.monitor.setBackgroundColor(self.backgroundColor)
    for y = y1, y2 do
        self.monitor.setCursorPos(x1, y)
        self.monitor.write(string.rep(" ", width))
    end

    -- Top border with title
    self.monitor.setBackgroundColor(self.borderColor)
    self.monitor.setCursorPos(x1, y1)
    self.monitor.write(string.rep(" ", width))

    if self.title and #self.title > 0 then
        local titleX = x1 + math.floor((width - #self.title) / 2)
        self.monitor.setTextColor(self.titleColor)
        self.monitor.setCursorPos(titleX, y1)
        self.monitor.write(self.title)
    end

    -- Bottom border
    self.monitor.setCursorPos(x1, y2)
    self.monitor.write(string.rep(" ", width))

    -- Reset
    self.monitor.setBackgroundColor(self.backgroundColor)
    self.monitor.setTextColor(self.textColor)
end

-- Show overlay with title and content lines
-- @param title Overlay title
-- @param lines Array of {text, color} or just strings
function Overlay:show(title, lines)
    self.title = title or ""
    self.content = lines or {}
    self.visible = true

    self:render()
end

-- Render the overlay
function Overlay:render()
    if not self.visible then
        return
    end

    local x1, y1, x2, y2 = self:calculateBounds(#self.content)
    local contentWidth = x2 - x1 - 1

    self:drawFrame(x1, y1, x2, y2)

    -- Draw content
    for i, line in ipairs(self.content) do
        local text, color
        if type(line) == "table" then
            text = line.text or line[1] or ""
            color = line.color or line[2] or self.textColor
        else
            text = tostring(line)
            color = self.textColor
        end

        -- Truncate if needed
        if #text > contentWidth then
            text = text:sub(1, contentWidth - 3) .. "..."
        end

        local y = y1 + 1 + i
        if y < y2 then
            self.monitor.setTextColor(color)
            self.monitor.setCursorPos(x1 + 1, y)
            self.monitor.write(text)
        end
    end

    self.monitor.setTextColor(colors.white)
    self.monitor.setBackgroundColor(colors.black)
end

-- Hide the overlay
function Overlay:hide()
    self.visible = false
end

-- Check if overlay is visible
function Overlay:isVisible()
    return self.visible
end

-- Get content area bounds (for placing widgets)
-- @return x1, y1, x2, y2 of content area
function Overlay:getContentBounds()
    local x1, y1, x2, y2 = self:calculateBounds(#self.content)
    return x1 + 1, y1 + 2, x2 - 1, y2 - 1
end

return Overlay
