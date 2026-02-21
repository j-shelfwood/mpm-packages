-- ScrollableList.lua
-- Enhanced scrollable list with pagination indicators, action buttons, and group headers.
-- Uses EventLoop helpers for monitor-specific touch filtering.

local Core = mpm('ui/Core')
local EventLoop = mpm('ui/EventLoop')

local ScrollableList = {}
ScrollableList.__index = ScrollableList

-- Create a new scrollable list.
-- @param monitor Monitor peripheral
-- @param items   Array of items. An item may be a plain value or a table.
--                Group headers are tables with a "_group" key:
--                  { _group = "Section Title" }
--                Regular items are anything else.
-- @param opts Configuration table:
--   title             Header text (default: "Select")
--   formatFn          Function(item) -> string or {text, color}
--   valueFn           Function(item) -> comparable value for selected tracking
--   pageSize          Items per page (default: auto)
--   showPageIndicator Show "Page X/Y" (default: true)
--   actions           Array of {label, action} footer buttons
--   cancelText        Cancel button text (default: "Cancel")
--   showCancel        Whether to show cancel (default: true)
--   selected          Currently selected item value (for highlighting)
--   onSelect          Callback(item, index) on selection
-- @return ScrollableList instance
function ScrollableList.new(monitor, items, opts)
    local self = setmetatable({}, ScrollableList)

    self.monitor = monitor
    opts = opts or {}

    self.title = opts.title or "Select"
    self.cancelText = opts.cancelText or "Cancel"
    self.showCancel = opts.showCancel ~= false
    self.showPageIndicator = opts.showPageIndicator ~= false
    self.actions = opts.actions or {}
    self.selected = opts.selected
    self.onSelect = opts.onSelect

    self.valueFn = opts.valueFn or function(item)
        if type(item) == "table" then
            return item.value or item.name or item.displayName or item
        end
        return item
    end

    self.formatFn = opts.formatFn or function(item)
        if type(item) == "table" then
            return item.label or item.name or item.displayName or tostring(item.value or item)
        end
        return tostring(item)
    end

    -- Flatten items: raw list may contain group sentinels mixed with regular items.
    -- We store the raw list (including headers) in self.items for rendering,
    -- but track selectableCount separately for page math.
    self.items = items or {}

    self.scrollOffset = 0
    self.width, self.height = monitor.getSize()

    local headerHeight = 1
    local footerHeight = (self.showCancel or #self.actions > 0) and 1 or 0
    local pageIndicatorHeight = self.showPageIndicator and 1 or 0
    local padding = 1

    self.pageSize = opts.pageSize or math.max(1, self.height - headerHeight - footerHeight - pageIndicatorHeight - padding)

    return self
end

-- Returns true if the item is a group header sentinel
local function isGroupHeader(item)
    return type(item) == "table" and item._group ~= nil
end

-- Count of visible rows (headers + items) for scroll math
function ScrollableList:getTotalRows()
    return #self.items
end

function ScrollableList:getTotalPages()
    return math.max(1, math.ceil(self:getTotalRows() / self.pageSize))
end

function ScrollableList:getCurrentPage()
    return math.floor(self.scrollOffset / self.pageSize) + 1
end

function ScrollableList:getLayout()
    local titleHeight = 1
    local footerHeight = (self.showCancel or #self.actions > 0) and 1 or 0
    local pageIndicatorHeight = self.showPageIndicator and 1 or 0

    local startY = titleHeight + 1
    local contentHeight = self.height - titleHeight - footerHeight - pageIndicatorHeight
    local maxVisible = math.max(1, contentHeight)

    return {
        titleY          = 1,
        startY          = startY,
        maxVisible      = maxVisible,
        pageIndicatorY  = self.showPageIndicator and (self.height - footerHeight) or nil,
        footerY         = footerHeight > 0 and self.height or nil
    }
end

function ScrollableList:render()
    local layout = self:getLayout()

    Core.clear(self.monitor)

    -- Title bar
    Core.drawBar(self.monitor, layout.titleY, self.title, Core.COLORS.titleBar, Core.COLORS.titleText)

    -- Items
    local visibleCount = math.min(layout.maxVisible, #self.items - self.scrollOffset)

    for i = 1, visibleCount do
        local itemIndex = i + self.scrollOffset
        local item = self.items[itemIndex]
        if not item then break end

        local y = layout.startY + i - 1

        if isGroupHeader(item) then
            -- Group header row: dimmed separator line
            self.monitor.setBackgroundColor(Core.COLORS.background)
            self.monitor.setTextColor(colors.gray)
            self.monitor.setCursorPos(1, y)

            local label = item._group
            -- Build: "- Label --..."
            local prefix = "\x97 " .. label .. " "
            local dashCount = math.max(0, self.width - #prefix)
            local line = prefix .. string.rep("\x97", dashCount)
            self.monitor.write(line:sub(1, self.width))
        else
            -- Regular item
            local formatted = self.formatFn(item)
            local text, color
            if type(formatted) == "table" then
                text  = formatted.text  or formatted[1] or ""
                color = formatted.color or formatted[2] or Core.COLORS.text
            else
                text  = tostring(formatted)
                color = Core.COLORS.text
            end

            text = Core.truncate(text, self.width - 4)

            local isSelected = self.selected ~= nil and self.valueFn(item) == self.selected

            if isSelected then
                self.monitor.setBackgroundColor(Core.COLORS.selection)
                self.monitor.setTextColor(Core.COLORS.selectionText)
                self.monitor.setCursorPos(1, y)
                self.monitor.write(string.rep(" ", self.width))
                self.monitor.setCursorPos(2, y)
                self.monitor.write("> " .. text)
            else
                self.monitor.setBackgroundColor(Core.COLORS.background)
                self.monitor.setTextColor(color)
                self.monitor.setCursorPos(2, y)
                self.monitor.write("  " .. text)
            end
        end
    end

    -- Scroll indicators
    self.monitor.setBackgroundColor(Core.COLORS.background)
    self.monitor.setTextColor(Core.COLORS.textMuted)

    if self.scrollOffset > 0 then
        self.monitor.setCursorPos(self.width, layout.startY)
        self.monitor.write("^")
    end

    if self.scrollOffset + layout.maxVisible < #self.items then
        self.monitor.setCursorPos(self.width, layout.startY + layout.maxVisible - 1)
        self.monitor.write("v")
    end

    -- Page indicator
    if layout.pageIndicatorY then
        local pageText = "Page " .. self:getCurrentPage() .. "/" .. self:getTotalPages()
        self.monitor.setBackgroundColor(Core.COLORS.background)
        self.monitor.setTextColor(Core.COLORS.textMuted)
        local pageX = math.floor((self.width - #pageText) / 2)
        self.monitor.setCursorPos(pageX, layout.pageIndicatorY)
        self.monitor.write(pageText)
    end

    -- Footer
    if layout.footerY then
        self:renderFooter(layout.footerY)
    end

    Core.resetColors(self.monitor)
end

function ScrollableList:renderFooter(y)
    local buttons = {}

    for _, action in ipairs(self.actions) do
        table.insert(buttons, { label = action.label, action = action.action })
    end

    if self.showCancel then
        table.insert(buttons, { label = self.cancelText, action = "cancel" })
    end

    if #buttons == 0 then return end

    local totalWidth = 0
    for _, btn in ipairs(buttons) do
        totalWidth = totalWidth + #btn.label + 2
    end
    totalWidth = totalWidth + (#buttons - 1)

    local startX = math.floor((self.width - totalWidth) / 2) + 1
    local x = startX

    self.footerButtons = {}

    for _, btn in ipairs(buttons) do
        local btnWidth = #btn.label + 2
        self.footerButtons[btn.action] = { x1 = x, x2 = x + btnWidth - 1, y = y }
        self.monitor.setBackgroundColor(Core.COLORS.cancelButton)
        self.monitor.setTextColor(Core.COLORS.titleText)
        self.monitor.setCursorPos(x, y)
        self.monitor.write(" " .. btn.label .. " ")
        x = x + btnWidth + 1
    end
end

-- Handle touch event.
-- Group header rows return nil (non-selectable).
-- @return "scroll_up"|"scroll_down"|"page_up"|"page_down"|"cancel"|action|{item,index}|nil
function ScrollableList:handleTouch(x, y)
    local layout = self:getLayout()

    -- Footer buttons
    if self.footerButtons then
        for action, zone in pairs(self.footerButtons) do
            if y == zone.y and x >= zone.x1 and x <= zone.x2 then
                return action
            end
        end
    end

    -- Scroll up indicator
    if y == layout.startY and x == self.width and self.scrollOffset > 0 then
        return "scroll_up"
    end

    -- Scroll down indicator
    local lastVisibleY = layout.startY + layout.maxVisible - 1
    if y == lastVisibleY and x == self.width then
        if self.scrollOffset + layout.maxVisible < #self.items then
            return "scroll_down"
        end
    end

    -- Page indicator
    if layout.pageIndicatorY and y == layout.pageIndicatorY then
        if x < self.width / 2 then return "page_up" else return "page_down" end
    end

    -- Item area
    if y >= layout.startY and y < layout.startY + layout.maxVisible then
        local itemIndex = (y - layout.startY + 1) + self.scrollOffset
        if itemIndex >= 1 and itemIndex <= #self.items then
            local item = self.items[itemIndex]
            -- Group headers are non-selectable
            if isGroupHeader(item) then return nil end
            return { item = item, index = itemIndex }
        end
    end

    return nil
end

function ScrollableList:scrollBy(delta)
    local newOffset = self.scrollOffset + delta
    local maxOffset = math.max(0, #self.items - self:getLayout().maxVisible)
    self.scrollOffset = math.max(0, math.min(newOffset, maxOffset))
end

function ScrollableList:goToPage(pageNum)
    local maxPage = self:getTotalPages()
    pageNum = math.max(1, math.min(pageNum, maxPage))
    self.scrollOffset = (pageNum - 1) * self.pageSize
end

-- Show the list and wait for a selectable item to be chosen.
-- @return Selected item, index  OR  nil if cancelled/detached
function ScrollableList:show()
    local monitorName = peripheral.getName(self.monitor)

    while true do
        self.width, self.height = self.monitor.getSize()
        self:render()

        local kind, x, y = EventLoop.waitForMonitorEvent(monitorName)

        if kind == "detach" then
            return nil
        elseif kind == "resize" then
            -- redraw
        elseif kind == "touch" then
            local result = self:handleTouch(x, y)

            if result == nil then
                -- no-op (header tap, dead zone)
            elseif result == "cancel" then
                return nil
            elseif result == "scroll_up" then
                self:scrollBy(-1)
            elseif result == "scroll_down" then
                self:scrollBy(1)
            elseif result == "page_up" then
                self:goToPage(self:getCurrentPage() - 1)
            elseif result == "page_down" then
                self:goToPage(self:getCurrentPage() + 1)
            elseif type(result) == "table" and result.item then
                if self.onSelect then
                    self.onSelect(result.item, result.index)
                end
                return result.item, result.index
            elseif type(result) == "string" then
                return result
            end
        end
    end
end

-- Non-blocking render
function ScrollableList:draw()
    self:render()
end

return ScrollableList
