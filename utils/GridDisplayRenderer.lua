-- GridDisplayRenderer.lua
-- Cell rendering logic for GridDisplay
-- Uses blit for efficient single-call-per-line rendering

local GridDisplayRenderer = {}

-- Truncate text with ellipsis in the middle
local ELLIPSIS = "..."

local function truncateText(text, maxLength)
    if not text then return "" end
    text = tostring(text)

    if maxLength < 1 then return "" end
    if #text <= maxLength then return text end
    if maxLength <= #ELLIPSIS then return text:sub(1, maxLength) end

    local prefixLength = math.floor((maxLength - #ELLIPSIS) / 2)
    local suffixLength = maxLength - #ELLIPSIS - prefixLength
    return text:sub(1, prefixLength) .. ELLIPSIS .. text:sub(-suffixLength)
end

-- Render cells in grid layout
-- @param monitor The monitor to render to
-- @param items Array of data items
-- @param formatFn Function(item) -> { lines={...}, colors={...}, aligns={...} }
-- @param layout Table: { cols, rows, cellWidth, cellHeight, gapX, gapY, startX, startY, visibleCount }
function GridDisplayRenderer.renderCells(monitor, items, formatFn, layout)
    local maxItems = layout.visibleCount or (layout.rows * layout.cols)
    local cellWidth = layout.cellWidth

    -- Get background color for blit
    local bgColor = monitor.getBackgroundColor()
    local bgHex = colors.toBlit(bgColor)

    for i, item in ipairs(items) do
        if i > maxItems then break end

        -- Calculate grid position (0-indexed)
        local col = (i - 1) % layout.cols
        local row = math.floor((i - 1) / layout.cols)

        -- Calculate pixel position
        local cellX = layout.startX + col * (cellWidth + layout.gapX)
        local cellY = layout.startY + row * (layout.cellHeight + layout.gapY)

        -- Get formatted content
        local ok, formatted = pcall(formatFn, item)
        if not ok or not formatted then
            formatted = { lines = {"Error"}, colors = {colors.red} }
        end

        formatted.lines = formatted.lines or {}
        formatted.colors = formatted.colors or {}

        -- Render each line
        for lineIdx, lineContent in ipairs(formatted.lines) do
            if lineIdx > layout.cellHeight then break end

            local yPos = cellY + lineIdx - 1

            -- Truncate content to cell width
            local content = truncateText(lineContent, cellWidth)

            -- Calculate X position based on alignment
            local xPos = cellX
            local lineAlign = formatted.aligns and formatted.aligns[lineIdx]

            if lineAlign == "right" and #content < cellWidth then
                xPos = cellX + (cellWidth - #content)
            elseif lineAlign == "center" and #content < cellWidth then
                xPos = cellX + math.floor((cellWidth - #content) / 2)
            end
            -- "left" or default: xPos stays at cellX

            -- Ensure valid cursor position
            xPos = math.max(1, xPos)
            yPos = math.max(1, yPos)

            -- Build blit strings
            local fgStr
            local lineColor = formatted.colors[lineIdx]

            if type(lineColor) == "table" then
                -- Per-character colors: lineColor is array of color constants
                fgStr = ""
                for j = 1, #content do
                    local charColor = lineColor[j] or colors.white
                    fgStr = fgStr .. colors.toBlit(charColor)
                end
            else
                -- Single color for entire line
                local fgHex = colors.toBlit(lineColor or colors.white)
                fgStr = string.rep(fgHex, #content)
            end

            local bgStr = string.rep(bgHex, #content)

            -- Render with blit (single call per line)
            monitor.setCursorPos(xPos, yPos)
            monitor.blit(content, fgStr, bgStr)
        end
    end
end

return GridDisplayRenderer
