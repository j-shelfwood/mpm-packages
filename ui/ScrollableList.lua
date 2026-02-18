-- ScrollableList.lua
-- Enhanced scrollable list with pagination indicators and action buttons
-- Extends List.lua pattern for interactive view usage
-- Uses EventUtils.pullEvent to preserve queued events in monitor coroutines

local Core = mpm('ui/Core')
local EventUtils = mpm('utils/EventUtils')

local ScrollableList = {}
ScrollableList.__index = ScrollableList

-- Create a new scrollable list
-- @param monitor Monitor peripheral
-- @param items Array of items to display
-- @param opts Configuration table:
--   title: Header text (default: "Select")
--   formatFn: Function to format item for display (receives item, returns string or {text, color})
--   pageSize: Items per page (default: auto-calculated from monitor height)
--   showPageIndicator: Show "Page X/Y" (default: true)
--   actions: Array of {label, action} for footer buttons
--   cancelText: Cancel button text (default: "Cancel")
--   showCancel: Whether to show cancel button (default: true)
--   selected: Currently selected item (for highlighting)
--   onSelect: Callback when item selected (receives item, index)
-- @return ScrollableList instance
function ScrollableList.new(monitor, items, opts)
    local self = setmetatable({}, ScrollableList)

    self.monitor = monitor
    self.items = items or {}
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

    self.scrollOffset = 0
    self.width, self.height = monitor.getSize()

    -- Calculate page size based on available space
    local headerHeight = 1
    local footerHeight = (self.showCancel or #self.actions > 0) and 1 or 0
    local pageIndicatorHeight = self.showPageIndicator and 1 or 0
    local padding = 1

    self.pageSize = opts.pageSize or math.max(1, self.height - headerHeight - footerHeight - pageIndicatorHeight - padding)

    return self
end

-- Get total number of pages
function ScrollableList:getTotalPages()
    return math.max(1, math.ceil(#self.items / self.pageSize))
end

-- Get current page number (1-indexed)
function ScrollableList:getCurrentPage()
    return math.floor(self.scrollOffset / self.pageSize) + 1
end

-- Calculate visible area layout
function ScrollableList:getLayout()
    local titleHeight = 1
    local footerHeight = (self.showCancel or #self.actions > 0) and 1 or 0
    local pageIndicatorHeight = self.showPageIndicator and 1 or 0

    local startY = titleHeight + 1
    local contentHeight = self.height - titleHeight - footerHeight - pageIndicatorHeight
    local maxVisible = math.max(1, contentHeight)

    return {
        titleY = 1,
        startY = startY,
        maxVisible = maxVisible,
        pageIndicatorY = self.showPageIndicator and (self.height - footerHeight) or nil,
        footerY = footerHeight > 0 and self.height or nil
    }
end

-- Render the list
function ScrollableList:render()
    local layout = self:getLayout()

    Core.clear(self.monitor)

    -- Title bar
    Core.drawBar(self.monitor, layout.titleY, self.title, Core.COLORS.titleBar, Core.COLORS.titleText)

    -- Items list
    local visibleCount = math.min(layout.maxVisible, #self.items - self.scrollOffset)

    for i = 1, visibleCount do
        local itemIndex = i + self.scrollOffset
        local item = self.items[itemIndex]

        if item then
            local y = layout.startY + i - 1
            local formatted = self.formatFn(item)

            local text, color
            if type(formatted) == "table" then
                text = formatted.text or formatted[1] or ""
                color = formatted.color or formatted[2] or Core.COLORS.text
            else
                text = tostring(formatted)
                color = Core.COLORS.text
            end

            -- Truncate if too long
            text = Core.truncate(text, self.width - 4)

            -- Check if this is the selected item
            local isSelected = self.selected ~= nil and self.valueFn(item) == self.selected

            if isSelected then
                -- Highlighted row
                self.monitor.setBackgroundColor(Core.COLORS.selection)
                self.monitor.setTextColor(Core.COLORS.selectionText)
                self.monitor.setCursorPos(1, y)
                self.monitor.write(string.rep(" ", self.width))
                self.monitor.setCursorPos(2, y)
                self.monitor.write("> " .. text)
            else
                -- Normal row
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

    -- Footer with actions and cancel
    if layout.footerY then
        self:renderFooter(layout.footerY)
    end

    Core.resetColors(self.monitor)
end

-- Render footer with action buttons
function ScrollableList:renderFooter(y)
    local buttons = {}

    -- Add custom action buttons
    for _, action in ipairs(self.actions) do
        table.insert(buttons, { label = action.label, action = action.action })
    end

    -- Add cancel button
    if self.showCancel then
        table.insert(buttons, { label = self.cancelText, action = "cancel" })
    end

    if #buttons == 0 then return end

    -- Calculate button positions
    local totalWidth = 0
    for _, btn in ipairs(buttons) do
        totalWidth = totalWidth + #btn.label + 2  -- 1 space padding each side
    end
    totalWidth = totalWidth + (#buttons - 1)  -- gaps between buttons

    local startX = math.floor((self.width - totalWidth) / 2) + 1
    local x = startX

    self.footerButtons = {}

    for _, btn in ipairs(buttons) do
        local btnWidth = #btn.label + 2

        -- Store button zone for touch handling
        self.footerButtons[btn.action] = {
            x1 = x,
            x2 = x + btnWidth - 1,
            y = y
        }

        -- Draw button
        self.monitor.setBackgroundColor(Core.COLORS.cancelButton)
        self.monitor.setTextColor(Core.COLORS.titleText)
        self.monitor.setCursorPos(x, y)
        self.monitor.write(" " .. btn.label .. " ")

        x = x + btnWidth + 1
    end
end

-- Handle touch event
-- @return "scroll_up", "scroll_down", "page_up", "page_down", "cancel", action string, or {item, index}
function ScrollableList:handleTouch(x, y)
    local layout = self:getLayout()

    -- Check footer buttons
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

    -- Page indicator touch (left half = prev page, right half = next page)
    if layout.pageIndicatorY and y == layout.pageIndicatorY then
        if x < self.width / 2 then
            return "page_up"
        else
            return "page_down"
        end
    end

    -- Item selection
    if y >= layout.startY and y < layout.startY + layout.maxVisible then
        local itemIndex = (y - layout.startY + 1) + self.scrollOffset
        if itemIndex >= 1 and itemIndex <= #self.items then
            return { item = self.items[itemIndex], index = itemIndex }
        end
    end

    return nil
end

-- Scroll by a number of items
function ScrollableList:scrollBy(delta)
    local newOffset = self.scrollOffset + delta
    local maxOffset = math.max(0, #self.items - self:getLayout().maxVisible)
    self.scrollOffset = math.max(0, math.min(newOffset, maxOffset))
end

-- Jump to a specific page
function ScrollableList:goToPage(pageNum)
    local maxPage = self:getTotalPages()
    pageNum = math.max(1, math.min(pageNum, maxPage))
    self.scrollOffset = (pageNum - 1) * self.pageSize
end

-- Show the list and wait for selection
-- @return Selected item, action string, or nil if cancelled
function ScrollableList:show()
    local monitorName = peripheral.getName(self.monitor)

    while true do
        self:render()

        local side, x, y
        repeat
            local _, touchSide, tx, ty = EventUtils.pullEvent("monitor_touch")
            side, x, y = touchSide, tx, ty
        until side == monitorName

        if side == monitorName then
            local result = self:handleTouch(x, y)

            if result == "cancel" then
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
                -- Item selected
                if self.onSelect then
                    self.onSelect(result.item, result.index)
                end
                return result.item, result.index
            elseif type(result) == "string" then
                -- Custom action
                return result
            end
        end
    end
end

-- Non-blocking: render list at current state without event loop
-- Use handleTouch separately for event processing
function ScrollableList:draw()
    self:render()
end

return ScrollableList
