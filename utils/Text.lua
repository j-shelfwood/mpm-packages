local Text = {}

-- Format a number with K/M/G suffixes
-- @param num Number to format
-- @param decimals Decimal places (default: 1)
-- @return Formatted string like "1.5K", "2.3M"
function Text.formatNumber(num, decimals)
    if not num then return "0" end
    decimals = decimals or 1
    local fmt = "%." .. decimals .. "f"

    local absNum = math.abs(num)
    local sign = num < 0 and "-" or ""

    if absNum >= 1000000000 then
        return sign .. string.format(fmt .. "G", absNum / 1000000000)
    elseif absNum >= 1000000 then
        return sign .. string.format(fmt .. "M", absNum / 1000000)
    elseif absNum >= 1000 then
        return sign .. string.format(fmt .. "K", absNum / 1000)
    else
        return sign .. tostring(math.floor(absNum))
    end
end

-- Prettify a namespaced ID (minecraft:diamond_ore -> Diamond Ore)
-- @param id Namespaced ID like "minecraft:diamond_ore"
-- @return Pretty name like "Diamond Ore"
function Text.prettifyName(id)
    if not id then return "Unknown" end
    local _, _, name = string.find(id, ":(.+)")
    if name then
        -- Replace underscores with spaces, capitalize first letter
        name = name:gsub("_", " ")
        return name:gsub("^%l", string.upper)
    end
    return id
end

-- Truncate text with ellipsis in the middle
-- @param text Text to truncate
-- @param maxLength Maximum length
-- @return Truncated text like "lon...ing"
function Text.truncateMiddle(text, maxLength)
    if not text then return "" end
    text = tostring(text)
    if #text <= maxLength then return text end
    if maxLength <= 3 then return text:sub(1, maxLength) end

    local prefixLen = math.floor((maxLength - 3) / 2)
    local suffixLen = maxLength - 3 - prefixLen
    return text:sub(1, prefixLen) .. "..." .. text:sub(-suffixLen)
end

-- Format fluid amount in millibuckets to human-readable
-- @param amount_mB Amount in millibuckets
-- @return Formatted string like "500mB", "1.5B", "10K B", "1.2M B"
function Text.formatFluidAmount(amount_mB)
    if not amount_mB then return "0mB" end
    local buckets = math.abs(amount_mB) / 1000

    if buckets < 1 then
        -- Less than 1 bucket: show millibuckets
        return string.format("%dmB", math.abs(amount_mB))
    elseif buckets < 1000 then
        -- 1-999 buckets
        return string.format("%.1fB", buckets)
    elseif buckets < 1000000 then
        -- 1K-999K buckets
        return string.format("%.1fK B", buckets / 1000)
    else
        -- 1M+ buckets
        return string.format("%.1fM B", buckets / 1000000)
    end
end

-- Function to shorten item names if they're too long
function Text.shortenName(name, maxLength)
    if #name <= maxLength then
        return name
    else
        local partLength = math.floor((maxLength - 1) / 2) -- subtract one to account for the hyphen
        return name:sub(1, partLength) .. "-" .. name:sub(-partLength)
    end
end

-- Convert color constant to blit hex character
-- @param color Color constant (e.g., colors.white)
-- @return string Single hex character (0-9, a-f)
function Text.colorToBlit(color)
    return colors.toBlit(color)
end

-- Build blit strings for a line with colored segments
-- @param segments Array of {text, fg, bg} tables
-- @param totalWidth Total line width to pad to
-- @param defaultBg Default background color (default: colors.black)
-- @return text, fgStr, bgStr for use with blit()
function Text.buildBlitLine(segments, totalWidth, defaultBg)
    local text, fgStr, bgStr = "", "", ""
    local defaultBgHex = colors.toBlit(defaultBg or colors.black)

    for _, seg in ipairs(segments) do
        local segText = tostring(seg.text or "")
        local fgHex = colors.toBlit(seg.fg or colors.white)
        local bgHex = colors.toBlit(seg.bg or defaultBg or colors.black)

        text = text .. segText
        fgStr = fgStr .. string.rep(fgHex, #segText)
        bgStr = bgStr .. string.rep(bgHex, #segText)
    end

    -- Pad to totalWidth if specified
    if totalWidth and #text < totalWidth then
        local pad = totalWidth - #text
        text = text .. string.rep(" ", pad)
        fgStr = fgStr .. string.rep(colors.toBlit(colors.white), pad)
        bgStr = bgStr .. string.rep(defaultBgHex, pad)
    end

    return text, fgStr, bgStr
end

-- Build a simple blit line from text with single fg/bg colors
-- @param text The text to write
-- @param fg Foreground color constant
-- @param bg Background color constant
-- @param totalWidth Optional width to pad to
-- @return text, fgStr, bgStr for use with blit()
function Text.simpleBlit(text, fg, bg, totalWidth)
    text = tostring(text or "")
    local fgHex = colors.toBlit(fg or colors.white)
    local bgHex = colors.toBlit(bg or colors.black)

    local fgStr = string.rep(fgHex, #text)
    local bgStr = string.rep(bgHex, #text)

    if totalWidth and #text < totalWidth then
        local pad = totalWidth - #text
        text = text .. string.rep(" ", pad)
        fgStr = fgStr .. string.rep(fgHex, pad)
        bgStr = bgStr .. string.rep(bgHex, pad)
    end

    return text, fgStr, bgStr
end

-- Format energy value with unit suffixes (T/G/M/k)
-- @param value Energy value (Joules, FE, etc.)
-- @param unit Unit suffix (default: "FE"). Pass "J" for Mekanism Joules.
-- @return Formatted string like "1.50GJ", "250kFE"
function Text.formatEnergy(value, unit)
    unit = unit or "FE"
    if not value then return "0" .. unit end
    local abs = math.abs(value)
    if abs >= 1e12 then
        return string.format("%.2fT%s", value / 1e12, unit)
    elseif abs >= 1e9 then
        return string.format("%.2fG%s", value / 1e9, unit)
    elseif abs >= 1e6 then
        return string.format("%.2fM%s", value / 1e6, unit)
    elseif abs >= 1e3 then
        return string.format("%.1fk%s", value / 1e3, unit)
    else
        return string.format("%.0f%s", value, unit)
    end
end

-- Alias for backwards compatibility
Text.prettifyItemIdentifier = Text.prettifyName

return Text
