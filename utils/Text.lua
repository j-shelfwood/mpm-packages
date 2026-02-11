local Text = {}

function Text.formatFluidAmount(amount_mB)
    local absAmount_mB = math.abs(amount_mB)
    local absAmount_B = absAmount_mB / 1000

    -- mb
    if absAmount_B < 10 then
        return string.format("%.1fmB", absAmount_mB)
    end

    -- B
    if absAmount_B < 1000 then
        local absAmount_B = absAmount_B / 1000
        return string.format("%.1f B", absAmount_B)
    end

    -- Thousand B
    if absAmount_B < 999999 then
        return string.format("%.1fK B", absAmount_B / 1000)
    end

    -- Million B
    return string.format("%.2fM B", absAmount_B / 1000000)
end

-- Function to prettify an item identifier (minecraft:chest -> Chest)
function Text.prettifyItemIdentifier(itemIdentifier)
    -- Remove everything before : (including other values than minecraft:)
    local name = itemIdentifier:match(":(.+)$")
    if name then
        -- Capitalize the first letter and return
        return name:gsub("^%l", string.upper)
    else
        -- If no colon is found, return the original identifier
        return itemIdentifier
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

return Text
