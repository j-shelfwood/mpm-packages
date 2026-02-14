-- GridDisplayRenderer.lua
-- Cell rendering logic for GridDisplay
-- Extracted from GridDisplay.lua for maintainability

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
-- @param data Array of items to display
-- @param format_callback Function to format items
-- @param layout Layout parameters from GridDisplay
-- @param options Rendering options (center_text, cell_padding)
function GridDisplayRenderer.renderCells(monitor, data, format_callback, layout, options)
    local maxItems = layout.rows * layout.columns
    local content_area = layout.cell_width - (options.cell_padding * 2)
    content_area = math.max(1, content_area)

    -- Get background color for blit
    local bgColor = monitor.getBackgroundColor()
    local bgHex = colors.toBlit(bgColor)

    for i, item in ipairs(data) do
        if i > maxItems then
            break
        end

        -- Calculate grid position (1-indexed)
        local column = ((i - 1) % layout.columns) + 1
        local row = math.floor((i - 1) / layout.columns) + 1

        -- Calculate pixel position
        local cell_x = layout.start_x + (column - 1) * (layout.cell_width + layout.spacing_x)
        local cell_y = layout.start_y + (row - 1) * (layout.cell_height + layout.spacing_y)

        -- Get formatted content
        local ok, formatted = pcall(format_callback, item)
        if not ok or not formatted then
            formatted = {lines = {"Error"}, colors = {colors.red}}
        end

        formatted.lines = formatted.lines or {}
        formatted.colors = formatted.colors or {}

        -- Render each line using blit for efficiency
        for line_idx, line_content in ipairs(formatted.lines) do
            if line_idx > layout.cell_height then
                break
            end

            local y_pos = cell_y + line_idx - 1
            local x_pos = cell_x + options.cell_padding

            -- Truncate content
            local content = truncateText(line_content, content_area)

            local lineAlign = formatted.aligns and formatted.aligns[line_idx] or formatted.align
            if lineAlign == "right" and #content < content_area then
                x_pos = x_pos + (content_area - #content)
            elseif lineAlign == "center" or (not lineAlign and options.center_text) then
                if #content < content_area then
                    local leftPad = math.floor((content_area - #content) / 2)
                    x_pos = x_pos + leftPad
                end
            end

            -- Ensure valid cursor position
            x_pos = math.max(1, x_pos)
            y_pos = math.max(1, y_pos)

            -- Build blit strings
            local fgStr, bgStr
            local lineColor = formatted.colors[line_idx]

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

            bgStr = string.rep(bgHex, #content)

            -- Render with blit (single call vs setTextColor + write)
            monitor.setCursorPos(x_pos, y_pos)
            monitor.blit(content, fgStr, bgStr)
        end
    end
end

return GridDisplayRenderer
