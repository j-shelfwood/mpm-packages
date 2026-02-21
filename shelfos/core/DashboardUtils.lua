-- DashboardUtils.lua
-- Shared helper utilities for terminal/headless dashboard rendering.

local DashboardUtils = {}

function DashboardUtils.appendSample(samples, value, maxSamples)
    table.insert(samples, value)
    if #samples > maxSamples then
        table.remove(samples, 1)
    end
end

function DashboardUtils.average(samples)
    if #samples == 0 then return 0 end
    local total = 0
    for _, value in ipairs(samples) do
        total = total + value
    end
    return total / #samples
end

function DashboardUtils.maxValue(samples)
    local max = 0
    for _, value in ipairs(samples) do
        if value > max then
            max = value
        end
    end
    return max
end

function DashboardUtils.truncateText(text, maxLen)
    text = tostring(text or "")
    if #text <= maxLen then return text end
    if maxLen <= 3 then return text:sub(1, maxLen) end
    return text:sub(1, maxLen - 3) .. "..."
end

function DashboardUtils.formatUptime(ms)
    local seconds = math.floor((ms or 0) / 1000)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60

    if hours > 0 then
        return string.format("%dh %02dm %02ds", hours, minutes, secs)
    end
    if minutes > 0 then
        return string.format("%dm %02ds", minutes, secs)
    end
    return string.format("%ds", secs)
end

-- Compute evenly-sized column boxes within a horizontal region.
-- @param startX Left-most x coordinate (1-based)
-- @param totalWidth Width available from startX
-- @param columnCount Desired number of columns
-- @param minWidth Minimum width per column (default: 10)
-- @param gutter Spaces between columns (default: 2)
-- @return Array of { x = number, width = number }
function DashboardUtils.layoutColumns(startX, totalWidth, columnCount, minWidth, gutter)
    startX = startX or 1
    totalWidth = math.max(1, totalWidth or 1)
    columnCount = math.max(1, columnCount or 1)
    minWidth = math.max(1, minWidth or 10)
    gutter = math.max(0, gutter or 2)

    local maxColumns = columnCount
    while maxColumns > 1 do
        local needed = (maxColumns * minWidth) + ((maxColumns - 1) * gutter)
        if needed <= totalWidth then
            break
        end
        maxColumns = maxColumns - 1
    end

    local usableWidth = totalWidth - ((maxColumns - 1) * gutter)
    local baseWidth = math.floor(usableWidth / maxColumns)
    local remainder = usableWidth % maxColumns

    local columns = {}
    local x = startX
    for i = 1, maxColumns do
        local width = baseWidth + ((i <= remainder) and 1 or 0)
        table.insert(columns, { x = x, width = width })
        x = x + width + gutter
    end

    return columns
end

return DashboardUtils
