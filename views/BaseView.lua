-- BaseView.lua
-- Declarative view framework for ShelfOS monitors
-- Handles lifecycle, rendering, and error states consistently
--
-- Views define WHAT to show, framework handles HOW to render
--
-- Split modules:
--   BaseViewRenderers.lua - Rendering helpers (header, footer, grid, list)
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

local Renderers = mpm('views/BaseViewRenderers')

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
                Renderers.renderEmpty(self, emptyMsg)
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
                Renderers.renderEmpty(self, emptyMsg)
            end
            return
        end

        -- Render header (for grid/list views)
        local startY = 1
        if definition.header then
            local header = definition.header(self, data)
            startY = Renderers.renderHeader(self, header)
        end

        -- Render content based on view type
        if viewType == BaseView.Type.GRID then
            Renderers.renderGrid(self, data, definition.formatItem, startY, definition)
            -- Re-render header after grid (grid may have repositioned things)
            if definition.header then
                local header = definition.header(self, data)
                Renderers.renderHeader(self, header)
            end
        elseif viewType == BaseView.Type.LIST then
            Renderers.renderList(self, data, definition.formatItem, startY, definition)
        elseif viewType == BaseView.Type.INTERACTIVE then
            Renderers.renderInteractiveList(self, data, definition.formatItem, startY, definition)
        end

        -- Render footer
        if definition.footer then
            local footer = definition.footer(self, data)
            Renderers.renderFooter(self, footer)
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
        -- @param monitor Window buffer (from Monitor.lua)
        -- @param config View configuration
        -- @param peripheralName Name of the monitor peripheral (for overlay event filtering)
        new = function(monitor, config, peripheralName)
            config = config or {}
            local width, height = monitor.getSize()

            local self = {
                monitor = monitor,
                config = config,
                peripheralName = peripheralName,  -- For overlay touch event filtering
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
            return Renderers.handleInteractiveTouch(self, x, y, definition.onItemTouch)
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
                Renderers.renderError(self, errorMsg)
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
                    Renderers.renderError(self, errorMsg)
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
