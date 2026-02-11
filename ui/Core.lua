-- Core.lua
-- Shared UI constants and utility functions
-- Foundation for consistent widget styling

local Core = {}

-- Standard padding/spacing constants
Core.PADDING = 1
Core.BUTTON_PADDING = 1  -- Space inside buttons

-- Standard colors for consistent theming
Core.COLORS = {
    titleBar = colors.blue,
    titleText = colors.white,
    confirmButton = colors.green,
    cancelButton = colors.red,
    neutralButton = colors.gray,
    disabledButton = colors.gray,
    selection = colors.gray,
    selectionText = colors.white,
    text = colors.white,
    textMuted = colors.lightGray,
    background = colors.black
}

-- Calculate centered X position
-- @param containerWidth Total width of container
-- @param contentWidth Width of content to center
-- @return X position (1-indexed)
function Core.centerX(containerWidth, contentWidth)
    return math.floor((containerWidth - contentWidth) / 2) + 1
end

-- Pad text to width with alignment
-- @param text String to pad
-- @param width Target width
-- @param align Alignment: "left" (default), "center", or "right"
-- @return Padded string
function Core.padText(text, width, align)
    text = tostring(text or "")
    local textLen = #text
    local padding = width - textLen

    if padding <= 0 then
        return text:sub(1, width)
    end

    if align == "right" then
        return string.rep(" ", padding) .. text
    elseif align == "center" then
        local left = math.floor(padding / 2)
        return string.rep(" ", left) .. text .. string.rep(" ", padding - left)
    else -- left (default)
        return text .. string.rep(" ", padding)
    end
end

-- Truncate text with ellipsis if too long
-- @param text String to truncate
-- @param maxLen Maximum length
-- @return Truncated string with ... if needed
function Core.truncate(text, maxLen)
    text = tostring(text or "")
    if #text <= maxLen then
        return text
    end
    if maxLen <= 3 then
        return text:sub(1, maxLen)
    end
    return text:sub(1, maxLen - 3) .. "..."
end

-- Truncate in the middle (preserves start and end)
-- @param text String to truncate
-- @param maxLen Maximum length
-- @return Truncated string with ... in middle
function Core.truncateMiddle(text, maxLen)
    text = tostring(text or "")
    if #text <= maxLen then
        return text
    end
    if maxLen <= 5 then
        return Core.truncate(text, maxLen)
    end

    local sideLen = math.floor((maxLen - 3) / 2)
    local startPart = text:sub(1, sideLen)
    local endPart = text:sub(-sideLen)
    return startPart .. "..." .. endPart
end

-- Draw a full-width bar (title bar, button bar)
-- @param monitor Monitor peripheral
-- @param y Y position
-- @param text Text to display (centered)
-- @param bgColor Background color
-- @param fgColor Text color (default: white)
function Core.drawBar(monitor, y, text, bgColor, fgColor)
    local width = monitor.getSize()
    monitor.setBackgroundColor(bgColor)
    monitor.setTextColor(fgColor or colors.white)
    monitor.setCursorPos(1, y)
    monitor.write(Core.padText(text or "", width, "center"))
end

-- Draw a clickable bar (like a button spanning full width)
-- Returns bounds for hit detection
-- @param monitor Monitor peripheral
-- @param y Y position
-- @param text Text to display (centered)
-- @param bgColor Background color
-- @param fgColor Text color
-- @return bounds table {x1, y1, x2, y2}
function Core.drawClickableBar(monitor, y, text, bgColor, fgColor)
    local width = monitor.getSize()
    Core.drawBar(monitor, y, text, bgColor, fgColor)
    return {x1 = 1, y1 = y, x2 = width, y2 = y}
end

-- Check if coordinates are within bounds
-- @param x X coordinate
-- @param y Y coordinate
-- @param bounds Table with x1, y1, x2, y2
-- @return boolean
function Core.inBounds(x, y, bounds)
    return x >= bounds.x1 and x <= bounds.x2 and y >= bounds.y1 and y <= bounds.y2
end

-- Reset monitor colors to defaults
-- @param monitor Monitor peripheral
function Core.resetColors(monitor)
    monitor.setBackgroundColor(Core.COLORS.background)
    monitor.setTextColor(Core.COLORS.text)
end

-- Clear monitor with background color
-- @param monitor Monitor peripheral
function Core.clear(monitor)
    Core.resetColors(monitor)
    monitor.clear()
end

return Core
