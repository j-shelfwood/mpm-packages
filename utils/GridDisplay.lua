-- GridDisplay.lua
-- Responsive grid layout for CC:Tweaked monitors
-- Automatically scales and arranges items in a grid with full width utilization
--
-- ============================================================================
-- BUFFER COMPATIBILITY (see docs/RENDERING_ARCHITECTURE.md)
-- ============================================================================
-- This module is designed for window-buffered rendering:
--   - Does NOT call setTextScale() (Monitor.lua sets once)
--   - Does NOT clear by default (buffer handles clearing)
--   - Uses blit for efficient rendering
--
-- When used with ShelfOS, the "monitor" parameter is actually a window buffer
-- created by Monitor.lua, not a raw peripheral.
-- ============================================================================

local GridDisplayRenderer = mpm('utils/GridDisplayRenderer')

local GridDisplay = {}
GridDisplay.__index = GridDisplay

local ELLIPSIS = "..."

-- Create a new GridDisplay instance
-- @param monitor - The monitor peripheral (or window buffer) to render to
-- @param options - Table:
--   columns: Fixed column count (nil = auto-calculate to maximize usage)
--   cellHeight: Lines per cell (default: 2)
--   gap: { x = horizontal gap, y = vertical gap } (default: {x=1, y=0})
--   headerRows: Reserved rows at top for header (default: 0)
--   minCellWidth: Minimum width per cell for auto-columns (default: 16)
function GridDisplay.new(monitor, options)
    if not monitor then
        error("GridDisplay requires a monitor peripheral")
    end

    options = options or {}

    local self = setmetatable({}, GridDisplay)
    self.monitor = monitor

    -- Layout parameters
    self.fixedColumns = options.columns       -- nil = auto
    self.cellHeight = options.cellHeight or 2
    self.gapX = (options.gap and options.gap.x) or 1
    self.gapY = (options.gap and options.gap.y) or 0
    self.headerRows = options.headerRows or 0
    self.minCellWidth = options.minCellWidth or 16

    -- Cached layout (set by layout())
    self._layout = nil

    return self
end

-- Truncate text with ellipsis in the middle
function GridDisplay.truncateText(text, maxLength)
    if not text then return "" end
    text = tostring(text)

    if maxLength < 1 then return "" end
    if #text <= maxLength then return text end
    if maxLength <= #ELLIPSIS then return text:sub(1, maxLength) end

    local prefixLength = math.floor((maxLength - #ELLIPSIS) / 2)
    local suffixLength = maxLength - #ELLIPSIS - prefixLength
    return text:sub(1, prefixLength) .. ELLIPSIS .. text:sub(-suffixLength)
end

-- Calculate layout for the given number of items
-- @param itemCount Number of items to display
-- @return layout table { cols, rows, cellWidth, startX, startY, visibleCount }
function GridDisplay:layout(itemCount)
    local screenW, screenH = self.monitor.getSize()
    screenW = math.max(screenW, 1)
    screenH = math.max(screenH, 1)

    local availH = math.max(1, screenH - self.headerRows)

    if itemCount <= 0 then
        self._layout = {
            cols = 1, rows = 0, cellWidth = screenW,
            startX = 1, startY = self.headerRows + 1,
            visibleCount = 0, screenW = screenW, screenH = screenH
        }
        return self._layout
    end

    -- Calculate columns: maximize columns that fit
    local cols
    if self.fixedColumns then
        cols = math.max(1, math.min(self.fixedColumns, itemCount))
    else
        -- How many columns can we fit?
        -- Each column needs at least minCellWidth chars + gap (except last)
        -- (cols * minCellWidth) + ((cols-1) * gapX) <= screenW
        -- cols * (minCellWidth + gapX) - gapX <= screenW
        -- cols <= (screenW + gapX) / (minCellWidth + gapX)
        cols = math.max(1, math.floor((screenW + self.gapX) / (self.minCellWidth + self.gapX)))
        cols = math.min(cols, itemCount)  -- Don't create more columns than items
    end

    -- Calculate cell width: distribute available space evenly
    -- total_used = cols * cellWidth + (cols-1) * gapX = screenW
    -- cellWidth = (screenW - (cols-1) * gapX) / cols
    local cellWidth = math.max(1, math.floor((screenW - (cols - 1) * self.gapX) / cols))

    -- Readability guard: if cells are too narrow for readable text,
    -- reduce column count until cellWidth >= 14 or we're at 1 column.
    -- 14 chars allows names like "Redstone Dust" (13) to display fully.
    local MIN_READABLE_WIDTH = 14
    if not self.fixedColumns then
        while cols > 1 and cellWidth < MIN_READABLE_WIDTH do
            cols = cols - 1
            cellWidth = math.max(1, math.floor((screenW - (cols - 1) * self.gapX) / cols))
        end
    end

    -- Calculate rows
    local cellStepY = self.cellHeight + self.gapY
    local maxRows = math.max(1, math.floor((availH + self.gapY) / cellStepY))
    local rowsNeeded = math.ceil(itemCount / cols)
    local rows = math.min(rowsNeeded, maxRows)

    -- Visible items
    local visibleCount = math.min(itemCount, rows * cols)

    -- Center grid horizontally
    local gridWidth = cols * cellWidth + (cols - 1) * self.gapX
    local startX = math.max(1, math.floor((screenW - gridWidth) / 2) + 1)
    local startY = self.headerRows + 1

    self._layout = {
        cols = cols,
        rows = rows,
        cellWidth = cellWidth,
        startX = startX,
        startY = startY,
        visibleCount = visibleCount,
        screenW = screenW,
        screenH = screenH
    }

    return self._layout
end

-- Render items into the grid
-- @param items Array of data items
-- @param formatFn Function(item) -> { lines={...}, colors={...}, aligns={...} }
function GridDisplay:render(items, formatFn)
    if not items or #items == 0 then return end

    -- Calculate layout if needed
    if not self._layout then
        self:layout(#items)
    end

    GridDisplayRenderer.renderCells(self.monitor, items, formatFn, {
        cols = self._layout.cols,
        rows = self._layout.rows,
        cellWidth = self._layout.cellWidth,
        cellHeight = self.cellHeight,
        gapX = self.gapX,
        gapY = self.gapY,
        startX = self._layout.startX,
        startY = self._layout.startY,
        visibleCount = self._layout.visibleCount
    })
end

-- Get the current layout (for external use like touch handling)
function GridDisplay:getLayout()
    return self._layout
end

-- Invalidate cached layout (call when monitor resizes or items change)
function GridDisplay:invalidate()
    self._layout = nil
end

return GridDisplay
