-- BaseView.lua
-- Declarative view lifecycle contract with composable render/input mixins.

local Renderers = mpm('views/BaseViewRenderers')
local WithGrid = mpm('views/mixins/WithGrid')
local WithScroll = mpm('views/mixins/WithScroll')

local BaseView = {}

BaseView.Type = {
    GRID = "grid",
    LIST = "list",
    CUSTOM = "custom",
    INTERACTIVE = "interactive"
}

local function validateDefinition(def)
    if not def.getData then
        error("View must define getData(self) function")
    end

    local viewType = def.type or BaseView.Type.CUSTOM

    if viewType == BaseView.Type.GRID or viewType == BaseView.Type.LIST then
        if not def.formatItem then
            error(viewType .. " views must define formatItem(self, item) function")
        end
    elseif viewType == BaseView.Type.INTERACTIVE then
        if not def.formatItem then
            error("Interactive views must define formatItem(self, item) function")
        end
    elseif viewType == BaseView.Type.CUSTOM then
        if not def.render then
            error("Custom views must define render(self, data) function")
        end
    end

    return true
end

function BaseView.create(definition)
    validateDefinition(definition)

    local viewType = definition.type or BaseView.Type.CUSTOM

    local function doRender(self, data)
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)

        if data == nil then
            if definition.renderEmpty then
                definition.renderEmpty(self, data)
            else
                Renderers.renderEmpty(self, definition.emptyMessage or "No data")
            end
            return
        end

        if viewType == BaseView.Type.CUSTOM then
            definition.render(self, data)
            return
        end

        local isEmpty = type(data) == "table" and #data == 0
        if isEmpty then
            if definition.renderEmpty then
                definition.renderEmpty(self, data)
            else
                Renderers.renderEmpty(self, definition.emptyMessage or "No data")
            end
            return
        end

        local startY = 1
        if definition.header then
            local header = definition.header(self, data)
            startY = Renderers.renderHeader(self, header)
        end

        if viewType == BaseView.Type.GRID then
            WithGrid.render(self, data, definition.formatItem, startY, definition)
        elseif viewType == BaseView.Type.LIST then
            Renderers.renderList(self, data, definition.formatItem, startY, definition)
        elseif viewType == BaseView.Type.INTERACTIVE then
            Renderers.renderInteractiveList(self, data, definition.formatItem, startY, definition)
        end

        if definition.footer then
            local footer = definition.footer(self, data)
            Renderers.renderFooter(self, footer)
        end

        self.monitor.setTextColor(colors.white)
    end

    return {
        sleepTime = definition.sleepTime or 1,
        configSchema = definition.configSchema or {},
        listenEvents = definition.listenEvents or {},

        mount = definition.mount or function() return true end,

        new = function(monitor, config, peripheralName)
            config = config or {}
            local width, height = monitor.getSize()

            local self = {
                monitor = monitor,
                config = config,
                peripheralName = peripheralName,
                width = width,
                height = height,
                _initialized = false,
                _gridDisplay = nil,
                _scrollOffset = 0,
                _pageSize = nil,
                _touchZones = {},
                _data = nil,
                listenEvents = definition.listenEvents or {}
            }

            if viewType == BaseView.Type.INTERACTIVE then
                WithScroll.initialize(self)
            end

            if definition.init then
                definition.init(self, config)
            end

            return self
        end,

        handleTouch = (function()
            if viewType == BaseView.Type.INTERACTIVE then
                return function(self, x, y)
                    local handled = WithScroll.handleTouch(self, x, y, definition.onItemTouch)
                    if handled then
                        return true
                    end
                    if definition.onTouch then
                        return definition.onTouch(self, x, y) and true or false
                    end
                    return false
                end
            end

            if definition.onTouch then
                return function(self, x, y)
                    return definition.onTouch(self, x, y) and true or false
                end
            end

            return nil
        end)(),

        getState = viewType == BaseView.Type.INTERACTIVE and function(self)
            return WithScroll.getState(self)
        end or nil,

        setState = viewType == BaseView.Type.INTERACTIVE and function(self, state)
            WithScroll.setState(self, state)
        end or nil,

        getData = function(self)
            return definition.getData(self)
        end,

        onEvent = function(self, event, ...)
            if definition.onEvent then
                return definition.onEvent(self, event, ...)
            end
            return false
        end,

        renderWithData = function(self, data)
            doRender(self, data)
        end,

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

        render = function(self)
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

            doRender(self, data)
        end
    }
end

function BaseView.grid(def)
    def.type = BaseView.Type.GRID
    return BaseView.create(def)
end

function BaseView.list(def)
    def.type = BaseView.Type.LIST
    return BaseView.create(def)
end

function BaseView.custom(def)
    def.type = BaseView.Type.CUSTOM
    return BaseView.create(def)
end

function BaseView.interactive(def)
    def.type = BaseView.Type.INTERACTIVE
    return BaseView.create(def)
end

return BaseView
