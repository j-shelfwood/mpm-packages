-- Overlay.lua
-- Modal overlay rendering for monitors
-- Provides a semi-modal UI layer on top of existing content
-- Enhanced with configurable margins and footer support

local Core = mpm('ui/Core')

local Overlay = {}
Overlay.__index = Overlay

-- Create a new overlay for a monitor
-- @param monitor The monitor peripheral
-- @param opts Configuration table:
--   margin: Margin from screen edges (default: 1)
--   footerHeight: Height reserved for buttons at bottom (default: 2)
-- @return Overlay instance
function Overlay.new(monitor, opts)
    if not monitor then
        error("Overlay requires a monitor peripheral")
    end

    opts = opts or {}

    local self = setmetatable({}, Overlay)
    self.monitor = monitor
    self.width, self.height = monitor.getSize()
    self.visible = false
    self.title = ""
    self.content = {}
    self.margin = opts.margin or 1
    self.footerHeight = opts.footerHeight or 2

    -- Colors
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

-- Calculate overlay bounds (centered, with margin)
-- @param contentHeight Number of content lines
-- @param contentWidth Desired content width (nil = auto based on margin)
-- @return x1, y1, x2, y2 (overlay bounds)
function Overlay:calculateBounds(contentHeight, contentWidth)
    -- Auto-calculate width from margin
    if not contentWidth then
        contentWidth = self.width - (self.margin * 2)
    end

    -- Add space for title bar, content padding, and footer
    local totalHeight = contentHeight + 2 + self.footerHeight  -- title + border + footer

    local x1 = math.floor((self.width - contentWidth) / 2) + 1
    local y1 = math.floor((self.height - totalHeight) / 2) + 1
    local x2 = x1 + contentWidth - 1
    local y2 = y1 + totalHeight - 1

    -- Clamp to screen with margin
    x1 = math.max(self.margin + 1, x1)
    y1 = math.max(self.margin + 1, y1)
    x2 = math.min(self.width - self.margin, x2)
    y2 = math.min(self.height - self.margin, y2)

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
        text = Core.truncate(text, contentWidth)

        local y = y1 + 1 + i
        if y < y2 - self.footerHeight then
            self.monitor.setTextColor(color)
            self.monitor.setCursorPos(x1 + 1, y)
            self.monitor.write(text)
        end
    end

    Core.resetColors(self.monitor)
end

-- Hide the overlay
function Overlay:hide()
    self.visible = false
end

-- Check if overlay is visible
function Overlay:isVisible()
    return self.visible
end

-- Get content area bounds (for placing content/widgets)
-- @return x1, y1, x2, y2 of content area (excludes title and footer)
function Overlay:getContentBounds()
    local x1, y1, x2, y2 = self:calculateBounds(#self.content)
    return x1 + 1, y1 + 2, x2 - 1, y2 - self.footerHeight - 1
end

-- Get footer area bounds (for placing buttons)
-- @return x1, y1, x2, y2 of footer area
function Overlay:getFooterBounds()
    local x1, y1, x2, y2 = self:calculateBounds(#self.content)
    return x1 + 1, y2 - self.footerHeight, x2 - 1, y2 - 1
end

-- Get full overlay bounds
-- @return x1, y1, x2, y2
function Overlay:getBounds()
    return self:calculateBounds(#self.content)
end

return Overlay
