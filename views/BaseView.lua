-- BaseView.lua
-- Declarative view framework for ShelfOS monitors
-- Handles lifecycle, rendering, and error states consistently
--
-- Views define WHAT to show, framework handles HOW to render

local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local GridDisplay = mpm('utils/GridDisplay')
local Yield = mpm('utils/Yield')

local BaseView = {}

-- View types
BaseView.Type = {
    GRID = "grid",       -- Grid of items using GridDisplay
    LIST = "list",       -- Vertical list of items
    CUSTOM = "custom"    -- Fully custom rendering
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

-- Create a view from a definition
function BaseView.create(definition)
    -- Validate at creation time
    validateDefinition(definition)

    local viewType = definition.type or BaseView.Type.CUSTOM

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
                _gridDisplay = nil
            }

            -- Call user's init to set up instance state
            if definition.init then
                definition.init(self, config)
            end

            return self
        end,

        -- Main render function (framework-managed)
        render = function(self)
            -- Set up monitor
            self.monitor.setBackgroundColor(colors.black)
            self.monitor.setTextColor(colors.white)
            self.monitor.clear()

            -- 1. Get data with error handling
            local ok, data = pcall(definition.getData, self)
            Yield.yield()

            if not ok then
                local errorMsg = definition.errorMessage or "Error loading data"
                if definition.renderError then
                    definition.renderError(self, errorMsg)
                else
                    defaultRenderError(self, errorMsg)
                end
                return
            end

            -- 2. Handle empty state
            local isEmpty = not data or (type(data) == "table" and #data == 0)
            if isEmpty and viewType ~= BaseView.Type.CUSTOM then
                if definition.renderEmpty then
                    definition.renderEmpty(self, data)
                else
                    local emptyMsg = definition.emptyMessage or "No data"
                    defaultRenderEmpty(self, emptyMsg)
                end
                return
            end

            -- 3. For custom views, delegate entirely to user's render
            if viewType == BaseView.Type.CUSTOM then
                definition.render(self, data)
                return
            end

            -- 4. Render header (for grid/list views)
            local startY = 1
            if definition.header then
                local header = definition.header(self, data)
                startY = renderHeader(self, header)
            end

            -- 5. Render content based on view type
            if viewType == BaseView.Type.GRID then
                renderGrid(self, data, definition.formatItem, startY, definition)
                -- Re-render header after grid (grid may have repositioned things)
                if definition.header then
                    local header = definition.header(self, data)
                    renderHeader(self, header)
                end
            elseif viewType == BaseView.Type.LIST then
                renderList(self, data, definition.formatItem, startY, definition)
            end

            -- 6. Render footer
            if definition.footer then
                local footer = definition.footer(self, data)
                renderFooter(self, footer)
            end

            -- Reset text color
            self.monitor.setTextColor(colors.white)
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

return BaseView
