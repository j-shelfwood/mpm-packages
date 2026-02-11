-- GridDisplay.lua
-- Responsive grid layout for CC:Tweaked monitors
-- Automatically scales and arranges items in a grid

local GridDisplay = {}
GridDisplay.__index = GridDisplay

-- Constants
local MIN_TEXT_SCALE = 0.5
local MAX_TEXT_SCALE = 2      -- Start at reasonable scale (5 is too zoomed)
local SCALE_DECREMENT = 0.5
local DEFAULT_CELL_WIDTH = 20
local DEFAULT_CELL_PADDING = 2  -- Padding inside each cell
local ELLIPSIS = "..."

-- Create a new GridDisplay instance
-- @param monitor - The monitor peripheral to render to
-- @param options - Optional table with: cell_width, spacing_x, spacing_y, padding
--                  OR a number for backwards compatibility (treated as cell_width)
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
    self.cell_width = options.cell_width or DEFAULT_CELL_WIDTH
    self.cell_padding = options.padding or DEFAULT_CELL_PADDING
    self.spacing_x = options.spacing_x or 1
    self.spacing_y = options.spacing_y or 1

    -- Cached layout parameters (set during calculate_cells)
    self.columns = 1
    self.rows = 1
    self.start_x = 1
    self.start_y = 1
    self.cell_height = 1
    self.scale = 1

    return self
end

-- Truncate text with ellipsis in the middle
-- @param text - Text to truncate
-- @param maxLength - Maximum length
function GridDisplay:truncateText(text, maxLength)
    if not text then return "" end
    text = tostring(text)

    if maxLength < 1 then
        return ""
    end

    if #text <= maxLength then
        return text
    end

    if maxLength <= #ELLIPSIS then
        return text:sub(1, maxLength)
    end

    local prefixLength = math.floor((maxLength - #ELLIPSIS) / 2)
    local suffixLength = maxLength - #ELLIPSIS - prefixLength
    return text:sub(1, prefixLength) .. ELLIPSIS .. text:sub(-suffixLength)
end

-- Determine the maximum cell height from all items
-- @param data - Array of items
-- @param format_callback - Function that returns {lines={...}, colors={...}}
function GridDisplay:determineCellHeight(data, format_callback)
    if not data or #data == 0 then
        return 1
    end

    local maxHeight = 1
    for _, item in ipairs(data) do
        local ok, formatted = pcall(format_callback, item)
        if ok and formatted and formatted.lines then
            maxHeight = math.max(maxHeight, #formatted.lines)
        end
    end

    return maxHeight
end

-- Calculate optimal grid layout for the given number of items
-- @param num_items - Number of items to display
function GridDisplay:calculate_cells(num_items)
    if num_items <= 0 then
        self.columns = 1
        self.rows = 0
        self.start_x = 1
        self.start_y = 1
        return
    end

    local scale = MAX_TEXT_SCALE

    while scale >= MIN_TEXT_SCALE do
        self.monitor.setTextScale(scale)
        local width, height = self.monitor.getSize()

        -- Ensure minimum dimensions
        width = math.max(width, 1)
        height = math.max(height, 1)

        -- Calculate how many columns we can fit
        local usable_width = width - self.spacing_x
        local cell_total_width = self.cell_width + self.spacing_x

        if cell_total_width <= 0 then
            cell_total_width = 1
        end

        local max_columns = math.max(1, math.floor(usable_width / cell_total_width))
        local required_rows = math.ceil(num_items / max_columns)

        -- Calculate how many rows we can fit
        local cell_total_height = self.cell_height + self.spacing_y

        if cell_total_height <= 0 then
            cell_total_height = 1
        end

        local usable_height = height - self.spacing_y
        local max_rows = math.max(1, math.floor(usable_height / cell_total_height))

        -- Check if this scale works
        if required_rows <= max_rows then
            -- Calculate centering offsets
            local total_grid_width = max_columns * cell_total_width - self.spacing_x
            local total_grid_height = required_rows * cell_total_height - self.spacing_y

            self.start_x = math.max(1, math.floor((width - total_grid_width) / 2) + 1)
            self.start_y = math.max(1, math.floor((height - total_grid_height) / 2) + 1)
            self.columns = max_columns
            self.rows = required_rows
            self.scale = scale
            return
        end

        scale = scale - SCALE_DECREMENT
    end

    -- Fallback to minimum scale
    self.scale = MIN_TEXT_SCALE
    self.monitor.setTextScale(MIN_TEXT_SCALE)

    local width, height = self.monitor.getSize()
    width = math.max(width, 1)
    height = math.max(height, 1)

    local cell_total_width = math.max(1, self.cell_width + self.spacing_x)
    local cell_total_height = math.max(1, self.cell_height + self.spacing_y)

    self.columns = math.max(1, math.floor(width / cell_total_width))
    self.rows = math.max(1, math.floor(height / cell_total_height))
    self.start_x = 1
    self.start_y = 1
end

-- Display data in a grid layout
-- @param data - Array of items to display
-- @param format_callback - Function(item) returning {lines={...}, colors={...}}
-- @param center_text - Whether to center text in cells (default: true)
function GridDisplay:display(data, format_callback, center_text)
    if center_text == nil then
        center_text = true
    end

    -- Handle nil/empty data
    if not data or #data == 0 then
        self.monitor.setTextScale(1)
        self.monitor.clear()
        local width, height = self.monitor.getSize()
        self.monitor.setTextColor(colors.lightGray)
        local msg = "No data"
        local x = math.max(1, math.floor((width - #msg) / 2) + 1)
        local y = math.max(1, math.floor(height / 2))
        self.monitor.setCursorPos(x, y)
        self.monitor.write(msg)
        self.monitor.setTextColor(colors.white)
        return
    end

    -- Validate format_callback
    if type(format_callback) ~= "function" then
        error("format_callback must be a function")
    end

    -- Determine cell height from data
    self.cell_height = self:determineCellHeight(data, format_callback)

    -- Calculate grid layout
    self:calculate_cells(#data)

    -- Clear and render
    self.monitor.clear()

    local maxItems = self.rows * self.columns
    local contentWidth = self.cell_width - (self.cell_padding * 2)
    contentWidth = math.max(1, contentWidth)

    for i, item in ipairs(data) do
        if i > maxItems then
            break
        end

        -- Calculate grid position
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

        -- Render each line
        for line_idx, line_content in ipairs(formatted.lines) do
            if line_idx > self.cell_height then
                break
            end

            local y_pos = cell_y + line_idx - 1
            local x_pos = cell_x + self.cell_padding

            -- Set color
            local color = formatted.colors[line_idx] or colors.white
            self.monitor.setTextColor(color)

            -- Truncate and format content
            local content = self:truncateText(line_content, contentWidth)

            if center_text then
                local padding = contentWidth - #content
                local leftPad = math.floor(padding / 2)
                x_pos = x_pos + leftPad
            end

            -- Ensure valid cursor position
            x_pos = math.max(1, x_pos)
            y_pos = math.max(1, y_pos)

            self.monitor.setCursorPos(x_pos, y_pos)
            self.monitor.write(content)
        end
    end

    -- Reset text color
    self.monitor.setTextColor(colors.white)
end

-- Display a simple message centered on the monitor
-- @param message - Text to display
-- @param color - Optional text color
function GridDisplay:displayMessage(message, color)
    self.monitor.setTextScale(1)
    self.monitor.clear()

    local width, height = self.monitor.getSize()
    self.monitor.setTextColor(color or colors.white)

    local x = math.max(1, math.floor((width - #message) / 2) + 1)
    local y = math.max(1, math.floor(height / 2))

    self.monitor.setCursorPos(x, y)
    self.monitor.write(message)
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

return GridDisplay
