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

return DashboardUtils
