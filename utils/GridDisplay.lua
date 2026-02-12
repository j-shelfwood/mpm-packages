-- GridDisplay.lua
-- Responsive grid layout for CC:Tweaked monitors
-- Automatically scales and arranges items in a grid with proper centering
--
-- ============================================================================
-- BUFFER COMPATIBILITY (see docs/RENDERING_ARCHITECTURE.md)
-- ============================================================================
-- This module is designed for window-buffered rendering:
--   - Does NOT call setTextScale() during rendering (Monitor.lua sets once)
--   - Does NOT clear by default (skipClear=true, buffer handles clearing)
--   - Uses cached scale values to avoid resize event loops
--
-- When used with ShelfOS, the "monitor" parameter is actually a window buffer
-- created by Monitor.lua, not a raw peripheral.
-- ============================================================================

local GridDisplay = {}
GridDisplay.__index = GridDisplay

-- Constants (legacy - scale is now managed by Monitor.lua)
local MIN_TEXT_SCALE = 0.5
local MAX_TEXT_SCALE = 1.5
local SCALE_DECREMENT = 0.5
local ELLIPSIS = "..."

-- Cache for text scale to avoid redundant setTextScale calls
-- setTextScale() can trigger monitor_resize events causing loops
local scaleCache = setmetatable({}, { __mode = "k" })

-- Create a new GridDisplay instance
-- @param monitor - The monitor peripheral to render to
-- @param options - Optional table with:
--   cell_width: Fixed cell width (nil = auto-calculate)
--   min_cell_width: Minimum cell width for auto mode (default: 12)
--   max_cell_width: Maximum cell width for auto mode (default: 25)
--   spacing_x: Horizontal spacing between cells (default: 1)
--   spacing_y: Vertical spacing between cells (default: 1)
--   padding: Padding inside cells (default: 1)
--   fill_width: Whether to stretch cells to fill width (default: true)
function GridDisplay.new(monitor, options)
    if not monitor then
        error("GridDisplay requires a monitor peripheral")
    end

    -- Backwards compatibility: if options is a number, treat as cell_width
    if type(options) == "number" then
        options = {cell_width = options}
    else
        options = options or {}
    end

    local self = setmetatable({}, GridDisplay)
    self.monitor = monitor

    -- Cell sizing options
    self.fixed_cell_width = options.cell_width  -- nil means auto
    self.min_cell_width = options.min_cell_width or 12
    self.max_cell_width = options.max_cell_width or 25
    self.fill_width = options.fill_width ~= false  -- default true

    -- Spacing and padding
    self.cell_padding = options.padding or 1
    self.spacing_x = options.spacing_x or 1
    self.spacing_y = options.spacing_y or 1

    -- Calculated layout (set during calculate_layout)
    self.columns = 1
    self.rows = 1
    self.start_x = 1
    self.start_y = 1
    self.cell_width = self.min_cell_width
    self.cell_height = 1
    self.scale = 1

    return self
end

-- Truncate text with ellipsis in the middle
function GridDisplay:truncateText(text, maxLength)
    if not text then return "" end
    text = tostring(text)

    if maxLength < 1 then return "" end
    if #text <= maxLength then return text end
    if maxLength <= #ELLIPSIS then return text:sub(1, maxLength) end

    local prefixLength = math.floor((maxLength - #ELLIPSIS) / 2)
    local suffixLength = maxLength - #ELLIPSIS - prefixLength
    return text:sub(1, prefixLength) .. ELLIPSIS .. text:sub(-suffixLength)
end

-- Analyze data to determine optimal cell dimensions
-- Returns: max_content_width, max_lines
function GridDisplay:analyzeContent(data, format_callback)
    if not data or #data == 0 then
        return self.min_cell_width, 1
    end

    local maxWidth = 0
    local maxLines = 1

    for _, item in ipairs(data) do
        local ok, formatted = pcall(format_callback, item)
        if ok and formatted and formatted.lines then
            maxLines = math.max(maxLines, #formatted.lines)
            for _, line in ipairs(formatted.lines) do
                maxWidth = math.max(maxWidth, #tostring(line))
            end
        end
    end

    -- Add padding to content width
    maxWidth = maxWidth + (self.cell_padding * 2)

    -- Clamp to min/max
    maxWidth = math.max(self.min_cell_width, math.min(self.max_cell_width, maxWidth))

    return maxWidth, maxLines
end

-- Calculate optimal number of columns for given item count and aspect ratio
function GridDisplay:calculateOptimalColumns(num_items, screen_width, screen_height, cell_width, cell_height)
    if num_items <= 0 then return 1 end

    local cell_total_width = cell_width + self.spacing_x
    local cell_total_height = cell_height + self.spacing_y

    -- Maximum columns that fit
    local max_cols = math.max(1, math.floor((screen_width + self.spacing_x) / cell_total_width))

    -- Maximum rows that fit
    local max_rows = math.max(1, math.floor((screen_height + self.spacing_y) / cell_total_height))

    -- Find column count that minimizes wasted space while fitting all items
    local best_cols = 1
    local best_waste = math.huge

    for cols = 1, math.min(max_cols, num_items) do
        local rows_needed = math.ceil(num_items / cols)
        if rows_needed <= max_rows then
            -- Calculate wasted cells (empty cells in last row)
            local total_cells = cols * rows_needed
            local waste = total_cells - num_items

            -- Also factor in aspect ratio - prefer more square-ish grids
            local grid_width = cols * cell_total_width
            local grid_height = rows_needed * cell_total_height
            local aspect_penalty = math.abs(grid_width - grid_height) * 0.1

            local score = waste + aspect_penalty
            if score < best_waste then
                best_waste = score
                best_cols = cols
            end
        end
    end

    return best_cols, max_cols
end

-- Helper to safely set text scale with caching
-- Avoids redundant calls that can trigger resize events
local function safeSetTextScale(monitor, scale)
    -- Check if monitor supports setTextScale (windows may not in all cases)
    if not monitor.setTextScale then
        return false
    end

    -- Check cache to avoid redundant calls
    local cached = scaleCache[monitor]
    if cached == scale then
        return false  -- No change needed
    end

    -- Apply scale and cache
    monitor.setTextScale(scale)
    scaleCache[monitor] = scale
    return true
end

-- Calculate layout for the given data
-- NOTE: With window-buffered rendering, text scale is set once at init.
-- This function no longer changes text scale dynamically to avoid
-- triggering resize events and breaking window dimensions.
function GridDisplay:calculate_layout(num_items, content_width, content_height, screen_width, screen_height)
    if num_items <= 0 then
        self.columns = 1
        self.rows = 0
        self.start_x = 1
        self.start_y = 1
        return true
    end

    -- Use current dimensions without changing text scale
    -- Monitor.lua sets text scale once at initialization
    if not screen_width or not screen_height then
        screen_width, screen_height = self.monitor.getSize()
    end
    screen_width = math.max(screen_width, 1)
    screen_height = math.max(screen_height, 1)

    -- Determine cell width
    local cell_width
    if self.fixed_cell_width then
        cell_width = self.fixed_cell_width
    elseif self.fill_width then
        -- Calculate cell width to fill screen evenly
        local optimal_cols, max_cols = self:calculateOptimalColumns(
            num_items, screen_width, screen_height, content_width, content_height
        )

        -- Calculate cell width that fills the screen with optimal_cols
        local available_width = screen_width + self.spacing_x
        cell_width = math.floor(available_width / optimal_cols) - self.spacing_x
        cell_width = math.max(self.min_cell_width, math.min(self.max_cell_width, cell_width))
    else
        cell_width = content_width
    end

    self.cell_width = cell_width
    self.cell_height = content_height

    -- Calculate grid dimensions
    local cell_total_width = cell_width + self.spacing_x
    local cell_total_height = content_height + self.spacing_y

    local max_cols = math.max(1, math.floor((screen_width + self.spacing_x) / cell_total_width))
    local max_rows = math.max(1, math.floor((screen_height + self.spacing_y) / cell_total_height))

    -- Use optimal column count (not max)
    local cols = math.min(max_cols, num_items)
    local rows_needed = math.ceil(num_items / cols)

    self.columns = cols
    self.rows = math.min(rows_needed, max_rows)
    self.scale = 1.0  -- Scale is managed by Monitor.lua

    -- Calculate centering using ACTUAL grid dimensions
    local actual_rows = math.min(rows_needed, max_rows)
    local actual_grid_width = cols * cell_total_width - self.spacing_x
    local actual_grid_height = actual_rows * cell_total_height - self.spacing_y

    self.start_x = math.max(1, math.floor((screen_width - actual_grid_width) / 2) + 1)
    self.start_y = math.max(1, math.floor((screen_height - actual_grid_height) / 2) + 1)

    return rows_needed <= max_rows
end

-- Display data in a grid layout
-- @param data - Array of items to display
-- @param format_callback - Function(item) returning {lines={...}, colors={...}, aligns={...}}
--   colors can be per-line (array) or per-character (array of arrays)
-- @param options - Table or boolean for backwards compatibility:
--   If boolean: treated as center_text
--   If table: {center_text=true, skipClear=true, startY=1}
-- NOTE: skipClear defaults to TRUE for window-buffered rendering
--       Monitor.lua handles clearing via the buffer
function GridDisplay:display(data, format_callback, options)
    -- Handle backwards compatibility: options can be boolean (center_text)
    local center_text = true
    local skipClear = true  -- Default TRUE: buffer handles clearing
    local startY = nil
    local reservedTop = 0

    if type(options) == "boolean" then
        center_text = options
    elseif type(options) == "table" then
        center_text = options.center_text ~= false
        skipClear = options.skipClear ~= false  -- Default true unless explicitly false
        startY = options.startY
    end

    -- Handle nil/empty data
    if not data or #data == 0 then
        -- Don't clear; just show message overlay
        self:displayMessage("No data", colors.lightGray, true)
        return
    end

    -- Validate format_callback
    if type(format_callback) ~= "function" then
        error("format_callback must be a function")
    end

    -- Analyze content to determine optimal cell size
    local content_width, content_height = self:analyzeContent(data, format_callback)

    -- Calculate grid layout
    if startY then
        reservedTop = math.max(0, startY - 1)
    end
    local screen_width, screen_height = self.monitor.getSize()
    screen_height = math.max(1, screen_height - reservedTop)
    self:calculate_layout(#data, content_width, content_height, screen_width, screen_height)

    if reservedTop > 0 then
        self.start_y = self.start_y + reservedTop
    end

    -- Legacy: clear if explicitly requested (skipClear=false)
    if not skipClear then
        self.monitor.clear()
    end

    local maxItems = self.rows * self.columns
    local content_area = self.cell_width - (self.cell_padding * 2)
    content_area = math.max(1, content_area)

    -- Get background color for blit
    local bgColor = self.monitor.getBackgroundColor()
    local bgHex = colors.toBlit(bgColor)

    for i, item in ipairs(data) do
        if i > maxItems then
            break
        end

        -- Calculate grid position (1-indexed)
        local column = ((i - 1) % self.columns) + 1
        local row = math.floor((i - 1) / self.columns) + 1

        -- Calculate pixel position
        local cell_x = self.start_x + (column - 1) * (self.cell_width + self.spacing_x)
        local cell_y = self.start_y + (row - 1) * (self.cell_height + self.spacing_y)

        -- Get formatted content
        local ok, formatted = pcall(format_callback, item)
        if not ok or not formatted then
            formatted = {lines = {"Error"}, colors = {colors.red}}
        end

        formatted.lines = formatted.lines or {}
        formatted.colors = formatted.colors or {}

        -- Render each line using blit for efficiency
        for line_idx, line_content in ipairs(formatted.lines) do
            if line_idx > self.cell_height then
                break
            end

            local y_pos = cell_y + line_idx - 1
            local x_pos = cell_x + self.cell_padding

            -- Truncate content
            local content = self:truncateText(line_content, content_area)

            local lineAlign = formatted.aligns and formatted.aligns[line_idx] or formatted.align
            if lineAlign == "right" and #content < content_area then
                x_pos = x_pos + (content_area - #content)
            elseif lineAlign == "center" or (not lineAlign and center_text) then
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
            self.monitor.setCursorPos(x_pos, y_pos)
            self.monitor.blit(content, fgStr, bgStr)
        end
    end
end

-- Display a simple message centered on the monitor
-- @param message Text to display
-- @param color Text color
-- @param skipClear If true, don't clear monitor (default true for buffered rendering)
function GridDisplay:displayMessage(message, color, skipClear)
    -- Don't change text scale - Monitor.lua manages scale
    -- Don't clear by default - Monitor.lua buffer handles this
    if skipClear ~= true then
        self.monitor.clear()
    end

    local width, height = self.monitor.getSize()
    local fgHex = colors.toBlit(color or colors.white)
    local bgHex = colors.toBlit(self.monitor.getBackgroundColor())

    local x = math.max(1, math.floor((width - #message) / 2) + 1)
    local y = math.max(1, math.floor(height / 2))

    self.monitor.setCursorPos(x, y)
    self.monitor.blit(message, string.rep(fgHex, #message), string.rep(bgHex, #message))
end

-- Get the current layout parameters
function GridDisplay:getLayout()
    return {
        columns = self.columns,
        rows = self.rows,
        start_x = self.start_x,
        start_y = self.start_y,
        cell_width = self.cell_width,
        cell_height = self.cell_height,
        scale = self.scale
    }
end

-- Legacy method for backwards compatibility
function GridDisplay:calculate_cells(num_items)
    self:calculate_layout(num_items, self.cell_width, self.cell_height)
end

-- Legacy method for backwards compatibility
function GridDisplay:determineCellHeight(data, format_callback)
    local _, height = self:analyzeContent(data, format_callback)
    return height
end

return GridDisplay
