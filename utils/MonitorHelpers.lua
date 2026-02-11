-- MonitorHelpers.lua
-- Common monitor drawing utilities used across views
-- Consolidates clearLine, writeAt, drawProgressBar patterns

local MonitorHelpers = {}

-- Clear a single line by overwriting with spaces
-- @param monitor Monitor peripheral
-- @param y Y position (row number)
-- @param width Optional width (defaults to monitor width)
function MonitorHelpers.clearLine(monitor, y, width)
    if not width then
        width = monitor.getSize()
    end
    monitor.setCursorPos(1, y)
    monitor.setBackgroundColor(colors.black)
    monitor.write(string.rep(" ", width))
end

-- Write text at a specific position with optional padding
-- @param monitor Monitor peripheral
-- @param x X position
-- @param y Y position
-- @param text Text to write
-- @param padWidth Optional width to pad to (clears trailing chars)
function MonitorHelpers.writeAt(monitor, x, y, text, padWidth)
    monitor.setCursorPos(x, y)
    if padWidth then
        text = text .. string.rep(" ", math.max(0, padWidth - #text))
    end
    monitor.write(text)
end

-- Write centered text on a line
-- @param monitor Monitor peripheral
-- @param y Y position
-- @param text Text to write
-- @param color Optional text color
function MonitorHelpers.writeCentered(monitor, y, text, color)
    local width = monitor.getSize()
    local x = math.floor((width - #text) / 2) + 1
    x = math.max(1, x)

    if color then
        monitor.setTextColor(color)
    end
    monitor.setCursorPos(x, y)
    monitor.write(text)
end

-- Draw a horizontal progress bar
-- @param monitor Monitor peripheral
-- @param x X position
-- @param y Y position
-- @param width Total bar width (including brackets)
-- @param percent Fill percentage (0-100)
-- @param fillColor Color for filled portion
-- @param emptyColor Color for empty portion (default: gray)
-- @param showBrackets Whether to show [ ] brackets (default: true)
function MonitorHelpers.drawProgressBar(monitor, x, y, width, percent, fillColor, emptyColor, showBrackets)
    showBrackets = showBrackets ~= false
    emptyColor = emptyColor or colors.gray
    percent = math.max(0, math.min(100, percent or 0))

    local barWidth = showBrackets and (width - 2) or width
    local filledWidth = math.floor(barWidth * percent / 100)

    monitor.setCursorPos(x, y)

    if showBrackets then
        monitor.setTextColor(colors.white)
        monitor.setBackgroundColor(colors.black)
        monitor.write("[")
    end

    -- Filled portion
    monitor.setBackgroundColor(fillColor)
    monitor.write(string.rep(" ", filledWidth))

    -- Empty portion
    monitor.setBackgroundColor(emptyColor)
    monitor.write(string.rep(" ", barWidth - filledWidth))

    if showBrackets then
        monitor.setBackgroundColor(colors.black)
        monitor.write("]")
    end

    -- Reset
    monitor.setBackgroundColor(colors.black)
end

-- Draw a vertical progress bar (fills from bottom to top)
-- @param monitor Monitor peripheral
-- @param x X position (center of bar)
-- @param y1 Top Y position
-- @param y2 Bottom Y position
-- @param percent Fill percentage (0-100)
-- @param fillColor Color for filled portion
-- @param emptyColor Color for empty portion (default: gray)
-- @param barWidth Width of the bar in characters (default: 3)
function MonitorHelpers.drawVerticalBar(monitor, x, y1, y2, percent, fillColor, emptyColor, barWidth)
    emptyColor = emptyColor or colors.gray
    barWidth = barWidth or 3
    percent = math.max(0, math.min(100, percent or 0))

    local height = y2 - y1 + 1
    local filledHeight = math.floor(height * percent / 100)

    local startX = x - math.floor(barWidth / 2)

    -- Draw empty portion (top)
    monitor.setBackgroundColor(emptyColor)
    for y = y1, y2 - filledHeight do
        monitor.setCursorPos(startX, y)
        monitor.write(string.rep(" ", barWidth))
    end

    -- Draw filled portion (bottom)
    monitor.setBackgroundColor(fillColor)
    for y = y2 - filledHeight + 1, y2 do
        monitor.setCursorPos(startX, y)
        monitor.write(string.rep(" ", barWidth))
    end

    -- Reset
    monitor.setBackgroundColor(colors.black)
end

-- Draw a simple box/frame
-- @param monitor Monitor peripheral
-- @param x1, y1 Top-left corner
-- @param x2, y2 Bottom-right corner
-- @param bgColor Background color
-- @param borderColor Optional border color (top/bottom rows)
function MonitorHelpers.drawBox(monitor, x1, y1, x2, y2, bgColor, borderColor)
    local width = x2 - x1 + 1

    for y = y1, y2 do
        monitor.setCursorPos(x1, y)
        if borderColor and (y == y1 or y == y2) then
            monitor.setBackgroundColor(borderColor)
        else
            monitor.setBackgroundColor(bgColor)
        end
        monitor.write(string.rep(" ", width))
    end

    monitor.setBackgroundColor(colors.black)
end

-- Get color based on percentage thresholds
-- @param percent Current percentage
-- @param thresholds Optional table {low=25, medium=75} or use defaults
-- @param colors Optional table {low=red, medium=yellow, high=green}
-- @return Color constant
function MonitorHelpers.getPercentColor(percent, thresholds, colorSet)
    thresholds = thresholds or {low = 25, medium = 75}
    colorSet = colorSet or {low = colors.red, medium = colors.yellow, high = colors.green}

    if percent <= thresholds.low then
        return colorSet.low
    elseif percent <= thresholds.medium then
        return colorSet.medium
    else
        return colorSet.high
    end
end

-- Get warning color (inverse of getPercentColor - low is good, high is bad)
-- @param value Current value
-- @param warningThreshold Value below which to warn
-- @return Color constant
function MonitorHelpers.getWarningColor(value, warningThreshold)
    if value < warningThreshold then
        return colors.red
    elseif value < warningThreshold * 2 then
        return colors.orange
    else
        return colors.white
    end
end

return MonitorHelpers
