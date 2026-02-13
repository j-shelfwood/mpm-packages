-- BaseView.lua
-- Declarative view framework for ShelfOS monitors
-- Handles lifecycle, rendering, and error states consistently
--
-- Views define WHAT to show, framework handles HOW to render
--
-- ============================================================================
-- RENDERING ARCHITECTURE (see docs/RENDERING_ARCHITECTURE.md)
-- ============================================================================
-- Monitor.lua uses WINDOW BUFFERING for flicker-free rendering:
--   1. Views receive a window buffer, not raw peripheral
--   2. Monitor.lua clears buffer before calling render()
--   3. Monitor.lua toggles visibility for atomic screen updates
--
-- RULES FOR VIEW DEVELOPMENT:
--   - DO NOT call self.monitor.clear() in render() - causes flashing
--   - DO NOT call Yield.yield() in render() - breaks multi-monitor
--   - DO NOT call setTextScale() - Monitor.lua sets scale once
--   - DO yield in getData() for large data processing
-- ============================================================================

local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local GridDisplay = mpm('utils/GridDisplay')
local Yield = mpm('utils/Yield')

local BaseView = {}

-- View types
BaseView.Type = {
    GRID = "grid",           -- Grid of items using GridDisplay
    LIST = "list",           -- Vertical list of items
    CUSTOM = "custom",       -- Fully custom rendering
    INTERACTIVE = "interactive"  -- Interactive list with touch handling
}

-- Validate view definition at load time
local function validateDefinition(def)
    -- getData is always required
    if not def.getData then
        error("View must define getData(self) function")
    end

    -- Type-specific validation
    local viewType = def.type or BaseView.Type.CUSTOM

    if viewType == BaseView.Type.GRID or viewType == BaseView.Type.LIST then
        if not def.formatItem then
            error(viewType .. " views must define formatItem(self, item) function")
        end
    elseif viewType == BaseView.Type.INTERACTIVE then
        if not def.formatItem then
            error("Interactive views must define formatItem(self, item) function")
        end
        -- onItemTouch is optional but recommended
    elseif viewType == BaseView.Type.CUSTOM then
        if not def.render then
            error("Custom views must define render(self, data) function")
        end
    end

    return true
end

-- Default empty state renderer
local function defaultRenderEmpty(self, message)
    message = message or "No data"
    MonitorHelpers.writeCentered(
        self.monitor,
        math.floor(self.height / 2),
        message,
        colors.gray
    )
end

-- Default error state renderer
local function defaultRenderError(self, message)
    MonitorHelpers.writeCentered(
        self.monitor,
        math.floor(self.height / 2),
        message or "Error",
        colors.red
    )
end

-- Render header at top of screen
local function renderHeader(self, header)
    if not header then return 1 end

    self.monitor.setCursorPos(1, 1)

    if type(header) == "string" then
        self.monitor.setTextColor(colors.white)
        self.monitor.write(Text.truncateMiddle(header, self.width))
    elseif type(header) == "table" then
        -- Primary text
        self.monitor.setTextColor(header.color or colors.white)
        local text = header.text or ""
        self.monitor.write(text)

        -- Secondary text (count, etc.)
        if header.secondary then
            self.monitor.setTextColor(header.secondaryColor or colors.gray)
            local remaining = self.width - #text
            self.monitor.write(Text.truncateMiddle(header.secondary, remaining))
        end
    end

    return 2  -- Content starts at row 2
end

-- Render footer at bottom of screen
local function renderFooter(self, footer)
    if not footer then return end

    self.monitor.setCursorPos(1, self.height)

    if type(footer) == "string" then
        self.monitor.setTextColor(colors.gray)
        self.monitor.write(Text.truncateMiddle(footer, self.width))
    elseif type(footer) == "table" then
        self.monitor.setTextColor(footer.color or colors.gray)
        self.monitor.write(Text.truncateMiddle(footer.text or "", self.width))
    end
end

-- Render grid layout
local function renderGrid(self, data, formatItem, startY, def)
    if not self._gridDisplay then
        self._gridDisplay = GridDisplay.new(self.monitor)
    end

    -- Limit items for performance
    local maxItems = def.maxItems or 50
    local displayData = {}
    for i = 1, math.min(#data, maxItems) do
        displayData[i] = data[i]
    end

    -- Display with skipClear since we already cleared
    self._gridDisplay:display(displayData, function(item)
        return formatItem(self, item)
    end, { skipClear = true, startY = startY })
end

-- Render list layout
local function renderList(self, data, formatItem, startY, def)
    local maxRows = self.height - startY
    local maxItems = def.maxItems or maxRows

    for i = 1, math.min(#data, maxItems, maxRows) do
        local item = data[i]
        local formatted = formatItem(self, item)
        local y = startY + i - 1

        if y > self.height - 1 then break end  -- Leave room for footer

        -- Render each line of the item
        if formatted.lines then
            local line = formatted.lines[1] or ""
            local color = formatted.colors and formatted.colors[1] or colors.white

            self.monitor.setCursorPos(1, y)
            self.monitor.setTextColor(color)
            self.monitor.write(Text.truncateMiddle(line, self.width))
        end
    end

    -- Show overflow indicator
    if #data > maxItems then
        self.monitor.setCursorPos(1, self.height - 1)
        self.monitor.setTextColor(colors.gray)
        self.monitor.write("+" .. (#data - maxItems) .. " more...")
    end
end

-- Render interactive list layout with touch zones
-- Stores touch zones in self._touchZones for handleTouch
local function renderInteractiveList(self, data, formatItem, startY, def)
    local footerHeight = def.footer and 1 or 0
    local pageIndicatorHeight = 1
    local availableRows = self.height - startY - footerHeight - pageIndicatorHeight

    -- Initialize pagination state if needed
    if not self._scrollOffset then
        self._scrollOffset = 0
    end
    if not self._pageSize then
        self._pageSize = math.max(1, availableRows)
    end

    -- Store data reference for touch handling
    self._data = data
    self._touchZones = {}

    -- Calculate pagination
    local totalItems = #data
    local totalPages = math.max(1, math.ceil(totalItems / self._pageSize))
    local currentPage = math.floor(self._scrollOffset / self._pageSize) + 1

    -- Render visible items
    local visibleCount = math.min(self._pageSize, totalItems - self._scrollOffset)

    for i = 1, visibleCount do
        local itemIndex = i + self._scrollOffset
        local item = data[itemIndex]

        if item then
            local y = startY + i - 1
            local formatted = formatItem(self, item)

            -- Store touch zone for this item
            self._touchZones[y] = {
                item = item,
                index = itemIndex,
                action = formatted.touchAction or "select",
                data = formatted.touchData or item
            }

            -- Render item
            if formatted.lines then
                local line = formatted.lines[1] or ""
                local color = formatted.colors and formatted.colors[1] or colors.white

                self.monitor.setCursorPos(1, y)
                self.monitor.setTextColor(color)
                self.monitor.write(Text.truncateMiddle(line, self.width - 1))

                -- Second line if space permits
                if formatted.lines[2] and i < visibleCount then
                    -- Compact: show on same line right-aligned
                    local line2 = formatted.lines[2]
                    local color2 = formatted.colors and formatted.colors[2] or colors.gray
                    local x = self.width - #line2
                    if x > #line + 2 then
                        self.monitor.setCursorPos(x, y)
                        self.monitor.setTextColor(color2)
                        self.monitor.write(line2)
                    end
                end
            end
        end
    end

    -- Scroll indicators
    self.monitor.setTextColor(colors.gray)
    if self._scrollOffset > 0 then
        self.monitor.setCursorPos(self.width, startY)
        self.monitor.write("^")
        self._touchZones["scroll_up"] = { y = startY, x = self.width }
    end

    local lastVisibleY = startY + visibleCount - 1
    if self._scrollOffset + self._pageSize < totalItems then
        self.monitor.setCursorPos(self.width, lastVisibleY)
        self.monitor.write("v")
        self._touchZones["scroll_down"] = { y = lastVisibleY, x = self.width }
    end

    -- Page indicator
    local pageY = self.height - footerHeight
    local pageText = "Page " .. currentPage .. "/" .. totalPages
    local pageX = math.floor((self.width - #pageText) / 2)
    self.monitor.setTextColor(colors.gray)
    self.monitor.setCursorPos(pageX, pageY)
    self.monitor.write(pageText)
    self._touchZones["page_indicator"] = { y = pageY }
end

-- Create a view from a definition
function BaseView.create(definition)
    -- Validate at creation time
    validateDefinition(definition)

    local viewType = definition.type or BaseView.Type.CUSTOM

    -- Internal render implementation (draws to monitor, no getData)
    -- Used by renderWithData and legacy render
    local function doRender(self, data)
        -- Set up text colors (buffer already cleared by Monitor.lua)
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)

        -- Handle nil data (getData returned nil - likely peripheral unavailable)
        if data == nil then
            if definition.renderEmpty then
                definition.renderEmpty(self, data)
            else
                local emptyMsg = definition.emptyMessage or "No data"
                defaultRenderEmpty(self, emptyMsg)
            end
            return
        end

        -- For custom views, delegate entirely to user's render
        -- (custom views handle their own empty table state)
        if viewType == BaseView.Type.CUSTOM then
            definition.render(self, data)
            return
        end

        -- Handle empty table state for grid/list views
        local isEmpty = type(data) == "table" and #data == 0
        if isEmpty then
            if definition.renderEmpty then
                definition.renderEmpty(self, data)
            else
                local emptyMsg = definition.emptyMessage or "No data"
                defaultRenderEmpty(self, emptyMsg)
            end
            return
        end

        -- Render header (for grid/list views)
        local startY = 1
        if definition.header then
            local header = definition.header(self, data)
            startY = renderHeader(self, header)
        end

        -- Render content based on view type
        if viewType == BaseView.Type.GRID then
            renderGrid(self, data, definition.formatItem, startY, definition)
            -- Re-render header after grid (grid may have repositioned things)
            if definition.header then
                local header = definition.header(self, data)
                renderHeader(self, header)
            end
        elseif viewType == BaseView.Type.LIST then
            renderList(self, data, definition.formatItem, startY, definition)
        elseif viewType == BaseView.Type.INTERACTIVE then
            renderInteractiveList(self, data, definition.formatItem, startY, definition)
        end

        -- Render footer
        if definition.footer then
            local footer = definition.footer(self, data)
            renderFooter(self, footer)
        end

        -- Reset text color
        self.monitor.setTextColor(colors.white)
    end

    return {
        sleepTime = definition.sleepTime or 1,
        configSchema = definition.configSchema or {},

        -- Mount check (can this view run?)
        mount = definition.mount or function() return true end,

        -- Create new instance
        new = function(monitor, config)
            config = config or {}
            local width, height = monitor.getSize()

            local self = {
                monitor = monitor,
                config = config,
                width = width,
                height = height,
                _initialized = false,
                _gridDisplay = nil,
                -- Interactive state
                _scrollOffset = 0,
                _pageSize = nil,
                _touchZones = {},
                _data = nil
            }

            -- Call user's init to set up instance state
            if definition.init then
                definition.init(self, config)
            end

            return self
        end,

        -- Handle touch event (for interactive views)
        -- @return true if touch was handled, false otherwise
        handleTouch = viewType == BaseView.Type.INTERACTIVE and function(self, x, y)
            if not self._touchZones then return false end

            -- Check scroll up
            local scrollUp = self._touchZones["scroll_up"]
            if scrollUp and y == scrollUp.y and x == self.width then
                self._scrollOffset = math.max(0, self._scrollOffset - 1)
                return true
            end

            -- Check scroll down
            local scrollDown = self._touchZones["scroll_down"]
            if scrollDown and y == scrollDown.y and x == self.width then
                local maxOffset = math.max(0, #(self._data or {}) - (self._pageSize or 1))
                self._scrollOffset = math.min(maxOffset, self._scrollOffset + 1)
                return true
            end

            -- Check page indicator (left = prev, right = next)
            local pageInd = self._touchZones["page_indicator"]
            if pageInd and y == pageInd.y then
                local pageSize = self._pageSize or 1
                local totalItems = #(self._data or {})
                if x < self.width / 2 then
                    -- Previous page
                    self._scrollOffset = math.max(0, self._scrollOffset - pageSize)
                else
                    -- Next page
                    local maxOffset = math.max(0, totalItems - pageSize)
                    self._scrollOffset = math.min(maxOffset, self._scrollOffset + pageSize)
                end
                return true
            end

            -- Check item touch zones
            local zone = self._touchZones[y]
            if zone and zone.item then
                -- Call view's onItemTouch handler (blocking overlay pattern)
                if definition.onItemTouch then
                    definition.onItemTouch(self, zone.item, zone.action)
                    return true
                end
            end

            return false
        end or nil,

        -- Get current scroll state (for persistence)
        getState = viewType == BaseView.Type.INTERACTIVE and function(self)
            return {
                scrollOffset = self._scrollOffset or 0,
                pageSize = self._pageSize
            }
        end or nil,

        -- Set scroll state
        setState = viewType == BaseView.Type.INTERACTIVE and function(self, state)
            if state then
                self._scrollOffset = state.scrollOffset or 0
                if state.pageSize then
                    self._pageSize = state.pageSize
                end
            end
        end or nil,

        -- ================================================================
        -- TWO-PHASE RENDER API (for Monitor.lua window buffering)
        -- ================================================================
        -- Phase 1: getData() - CAN yield, call while buffer VISIBLE
        -- Phase 2: renderWithData(data) - NO yields, call while buffer HIDDEN
        -- ================================================================

        -- Phase 1: Fetch data (may yield - safe for multi-monitor)
        -- Called by Monitor.lua BEFORE hiding buffer
        getData = function(self)
            return definition.getData(self)
        end,

        -- Phase 2: Render with pre-fetched data (no yields)
        -- Called by Monitor.lua AFTER hiding buffer
        renderWithData = function(self, data)
            doRender(self, data)
        end,

        -- Render error state (used when getData fails)
        renderError = function(self, errorMsg)
            self.monitor.setBackgroundColor(colors.black)
            self.monitor.setTextColor(colors.white)
            errorMsg = errorMsg or definition.errorMessage or "Error loading data"
            if definition.renderError then
                definition.renderError(self, errorMsg)
            else
                defaultRenderError(self, errorMsg)
            end
        end,

        -- Legacy render function (combines getData + render)
        -- NOTE: Monitor.lua should use getData/renderWithData for proper buffering
        -- This function exists for backwards compatibility with non-ShelfOS usage
        render = function(self)
            -- 1. Get data with error handling
            local ok, data = pcall(definition.getData, self)

            if not ok then
                self.monitor.setBackgroundColor(colors.black)
                self.monitor.setTextColor(colors.white)
                local errorMsg = definition.errorMessage or "Error loading data"
                if definition.renderError then
                    definition.renderError(self, errorMsg)
                else
                    defaultRenderError(self, errorMsg)
                end
                return
            end

            -- 2. Delegate to shared render implementation
            doRender(self, data)
        end
    }
end

-- Helper to create a simple grid view with minimal boilerplate
function BaseView.grid(def)
    def.type = BaseView.Type.GRID
    return BaseView.create(def)
end

-- Helper to create a simple list view with minimal boilerplate
function BaseView.list(def)
    def.type = BaseView.Type.LIST
    return BaseView.create(def)
end

-- Helper to create a custom view
function BaseView.custom(def)
    def.type = BaseView.Type.CUSTOM
    return BaseView.create(def)
end

-- Helper to create an interactive view with touch handling
-- Interactive views support:
--   - Scrollable list with pagination
--   - Touch zones auto-registered from formatItem
--   - onItemTouch handler for blocking overlays
--   - getState/setState for scroll persistence
function BaseView.interactive(def)
    def.type = BaseView.Type.INTERACTIVE
    return BaseView.create(def)
end

return BaseView
