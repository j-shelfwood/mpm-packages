-- ScrollableList.lua
-- Scrollable list with collapsible group headers and two-step item selection.
--
-- Group headers: items with {_group="Label"} are rendered as collapsible section
-- dividers. Tap a header to toggle collapse. Collapsed groups hide their children.
--
-- Two-step selection: tapping an item highlights it and shows action buttons in
-- the footer ([Select] [Configure] [Cancel]). A second tap on the same item
-- confirms "Select". This prevents accidental immediate navigation.
--
-- Scroll zones: the full right column acts as scroll up/down area when hovering
-- over the top or bottom visible row respectively.

local Core = mpm('ui/Core')
local EventLoop = mpm('ui/EventLoop')

local ScrollableList = {}
ScrollableList.__index = ScrollableList

-- Action constants returned from show()
ScrollableList.ACTION_SELECT    = "select"
ScrollableList.ACTION_CONFIGURE = "configure"
ScrollableList.ACTION_CANCEL    = "cancel"

-- Create a new scrollable list.
-- @param monitor  Monitor peripheral (wrapped)
-- @param items    Array of items. {_group="Label"} items are collapsible headers.
-- @param opts     Configuration:
--   title             string  Header bar text (default "Select")
--   formatFn          fn(item)->string|{text,color}  Item display
--   valueFn           fn(item)->comparable  For selected tracking
--   pageSize          number  Override auto page size
--   showPageIndicator bool    Show "Page X/Y" (default true)
--   actions           table   Extra footer buttons [{label,action}]
--   cancelText        string  Cancel label (default "Cancel")
--   showCancel        bool    (default true)
--   selected          value   Pre-highlight an item by value
--   twoStep           bool    Enable two-step selection (default true)
--   showConfigure     bool    Show Configure button in two-step footer (default true)
-- @return ScrollableList instance
function ScrollableList.new(monitor, items, opts)
    local self = setmetatable({}, ScrollableList)

    self.monitor  = monitor
    opts = opts or {}

    self.title            = opts.title or "Select"
    self.cancelText       = opts.cancelText or "Cancel"
    self.showCancel       = opts.showCancel ~= false
    self.showPageIndicator = opts.showPageIndicator ~= false
    self.actions          = opts.actions or {}
    self.selected         = opts.selected  -- value of currently selected item
    self.twoStep          = opts.twoStep ~= false  -- default ON
    self.showConfigure    = opts.showConfigure ~= false

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

    -- Raw item array (may include group sentinels)
    self.rawItems = items or {}

    -- Collapse state: groupLabel -> bool (true = collapsed)
    self.collapsed = {}

    -- Currently highlighted item value (two-step pending state)
    self.pendingValue = nil

    self.scrollOffset = 0
    self.width, self.height = monitor.getSize()

    local headerHeight        = 1
    local footerHeight        = 1  -- always 1 footer line (cancel at minimum)
    local pageIndicatorHeight = self.showPageIndicator and 1 or 0

    self.pageSize = opts.pageSize or math.max(1,
        self.height - headerHeight - footerHeight - pageIndicatorHeight - 1)

    return self
end

-- Returns true if item is a group header sentinel
local function isGroupHeader(item)
    return type(item) == "table" and item._group ~= nil
end

-- Build the visible (flat) item list respecting collapse state.
-- Returns array of items that should be rendered at current scroll position.
-- Each entry in the flat list is either a header or a regular item.
function ScrollableList:buildVisible()
    local visible = {}
    local currentGroup = nil

    for _, item in ipairs(self.rawItems) do
        if isGroupHeader(item) then
            currentGroup = item._group
            table.insert(visible, item)
        else
            -- Show item only if its group is not collapsed
            if not currentGroup or not self.collapsed[currentGroup] then
                table.insert(visible, item)
            end
        end
    end

    return visible
end

function ScrollableList:getLayout()
    local titleHeight         = 1
    local footerHeight        = 1
    local pageIndicatorHeight = self.showPageIndicator and 1 or 0
    local startY              = titleHeight + 1
    local contentHeight       = self.height - titleHeight - footerHeight - pageIndicatorHeight
    local maxVisible          = math.max(1, contentHeight)

    return {
        titleY         = 1,
        startY         = startY,
        maxVisible     = maxVisible,
        pageIndicatorY = self.showPageIndicator and (self.height - footerHeight) or nil,
        footerY        = self.height,
    }
end

function ScrollableList:getTotalPages(visible)
    return math.max(1, math.ceil(#visible / self.pageSize))
end

function ScrollableList:getCurrentPage()
    return math.floor(self.scrollOffset / self.pageSize) + 1
end

-- Render a group header row
function ScrollableList:renderGroupHeader(y, item)
    local isCollapsed = self.collapsed[item._group]
    local marker = isCollapsed and " [+]" or " [-]"
    local label = item._group .. marker
    local padded = label .. string.rep("\x97", math.max(0, self.width - #label))

    self.monitor.setBackgroundColor(colors.gray)
    self.monitor.setTextColor(colors.white)
    self.monitor.setCursorPos(1, y)
    self.monitor.write(padded:sub(1, self.width))
    self.monitor.setBackgroundColor(Core.COLORS.background)
end

-- Render a regular item row
function ScrollableList:renderItem(y, item)
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

    local val       = self.valueFn(item)
    local isSelected = self.selected ~= nil and val == self.selected
    local isPending  = self.pendingValue ~= nil and val == self.pendingValue

    if isPending then
        -- Two-step highlight: distinct color
        self.monitor.setBackgroundColor(colors.blue)
        self.monitor.setTextColor(colors.white)
        self.monitor.setCursorPos(1, y)
        self.monitor.write(string.rep(" ", self.width))
        self.monitor.setCursorPos(2, y)
        self.monitor.write("> " .. text)
        self.monitor.setBackgroundColor(Core.COLORS.background)
    elseif isSelected then
        self.monitor.setBackgroundColor(Core.COLORS.selection)
        self.monitor.setTextColor(Core.COLORS.selectionText)
        self.monitor.setCursorPos(1, y)
        self.monitor.write(string.rep(" ", self.width))
        self.monitor.setCursorPos(2, y)
        self.monitor.write("> " .. text)
        self.monitor.setBackgroundColor(Core.COLORS.background)
    else
        self.monitor.setBackgroundColor(Core.COLORS.background)
        self.monitor.setTextColor(color)
        self.monitor.setCursorPos(2, y)
        self.monitor.write("  " .. text)
    end
end

function ScrollableList:render()
    local layout  = self:getLayout()
    local visible = self:buildVisible()

    self.width, self.height = self.monitor.getSize()
    Core.clear(self.monitor)

    -- Title bar
    Core.drawBar(self.monitor, layout.titleY, self.title, Core.COLORS.titleBar, Core.COLORS.titleText)

    -- Items
    local visibleCount = math.min(layout.maxVisible, #visible - self.scrollOffset)

    for i = 1, visibleCount do
        local idx  = i + self.scrollOffset
        local item = visible[idx]
        if not item then break end

        local y = layout.startY + i - 1

        if isGroupHeader(item) then
            self:renderGroupHeader(y, item)
        else
            self:renderItem(y, item)
        end
    end

    -- Scroll indicators (right column)
    self.monitor.setBackgroundColor(Core.COLORS.background)
    self.monitor.setTextColor(Core.COLORS.textMuted)

    if self.scrollOffset > 0 then
        self.monitor.setCursorPos(self.width, layout.startY)
        self.monitor.write("^")
    end

    if self.scrollOffset + layout.maxVisible < #visible then
        self.monitor.setCursorPos(self.width, layout.startY + layout.maxVisible - 1)
        self.monitor.write("v")
    end

    -- Page indicator
    if layout.pageIndicatorY then
        local pageText = "Page " .. self:getCurrentPage() .. "/" .. self:getTotalPages(visible)
        self.monitor.setBackgroundColor(Core.COLORS.background)
        self.monitor.setTextColor(Core.COLORS.textMuted)
        local pageX = math.floor((self.width - #pageText) / 2)
        self.monitor.setCursorPos(pageX, layout.pageIndicatorY)
        self.monitor.write(pageText)
    end

    -- Footer
    self:renderFooter(layout.footerY)

    Core.resetColors(self.monitor)
end

-- Render footer buttons.
-- In two-step mode with a pending item: show [Select] [Configure] [Cancel]
-- Otherwise: show [Cancel] (plus any custom actions)
function ScrollableList:renderFooter(y)
    local buttons = {}

    if self.pendingValue ~= nil then
        -- Two-step action buttons
        table.insert(buttons, { label = "Select",    action = ScrollableList.ACTION_SELECT })
        if self.showConfigure then
            table.insert(buttons, { label = "Configure", action = ScrollableList.ACTION_CONFIGURE })
        end
        table.insert(buttons, { label = "Cancel",    action = ScrollableList.ACTION_CANCEL })
    else
        -- Normal footer: custom actions + cancel
        for _, action in ipairs(self.actions) do
            table.insert(buttons, action)
        end
        if self.showCancel then
            table.insert(buttons, { label = self.cancelText, action = ScrollableList.ACTION_CANCEL })
        end
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

        local bgColor = Core.COLORS.cancelButton
        if btn.action == ScrollableList.ACTION_SELECT then
            bgColor = colors.green
        elseif btn.action == ScrollableList.ACTION_CONFIGURE then
            bgColor = colors.blue
        end

        self.monitor.setBackgroundColor(bgColor)
        self.monitor.setTextColor(Core.COLORS.titleText)
        self.monitor.setCursorPos(x, y)
        self.monitor.write(" " .. btn.label .. " ")

        x = x + btnWidth + 1
    end

    self.monitor.setBackgroundColor(Core.COLORS.background)
end

-- Handle a touch event. Returns an action descriptor or nil.
-- Descriptors:
--   "cancel"                              User cancelled
--   "scroll_up" / "scroll_down"          Scroll arrow hit
--   "page_up" / "page_down"              Page indicator hit
--   { action="select",    item, index }   Two-step confirmed select
--   { action="configure", item, index }   Two-step configure
--   { action="pending",   item, index }   Item tapped, entering two-step
--   nil                                   No-op (header toggle handled internally, dead zone)
function ScrollableList:handleTouch(x, y, visible)
    local layout = self:getLayout()

    -- Footer buttons
    if self.footerButtons then
        for action, zone in pairs(self.footerButtons) do
            if y == zone.y and x >= zone.x1 and x <= zone.x2 then
                if action == ScrollableList.ACTION_SELECT or action == ScrollableList.ACTION_CONFIGURE then
                    -- Find the pending item
                    for idx, item in ipairs(visible) do
                        if not isGroupHeader(item) and self.valueFn(item) == self.pendingValue then
                            return { action = action, item = item, index = idx }
                        end
                    end
                end
                return action  -- "cancel" or custom
            end
        end
    end

    -- Scroll indicators (right column top/bottom of content area)
    if x == self.width then
        if y == layout.startY and self.scrollOffset > 0 then
            return "scroll_up"
        end
        local lastVisibleY = layout.startY + layout.maxVisible - 1
        if y == lastVisibleY and self.scrollOffset + layout.maxVisible < #visible then
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
        if itemIndex >= 1 and itemIndex <= #visible then
            local item = visible[itemIndex]

            if isGroupHeader(item) then
                -- Toggle collapse
                self.collapsed[item._group] = not self.collapsed[item._group]
                -- If collapsing and pending item was in this group, clear pending
                if self.pendingValue ~= nil and self.collapsed[item._group] then
                    self.pendingValue = nil
                end
                return nil  -- re-render only
            end

            local val = self.valueFn(item)

            if self.twoStep then
                if self.pendingValue == val then
                    -- Second tap on same item = confirm select
                    self.pendingValue = nil
                    return { action = ScrollableList.ACTION_SELECT, item = item, index = itemIndex }
                else
                    -- First tap: enter pending state
                    self.pendingValue = val
                    return { action = "pending", item = item, index = itemIndex }
                end
            else
                -- Direct selection (twoStep disabled)
                return { action = ScrollableList.ACTION_SELECT, item = item, index = itemIndex }
            end
        end
    end

    return nil
end

function ScrollableList:scrollBy(delta, visible)
    local newOffset = self.scrollOffset + delta
    local maxOffset = math.max(0, #visible - self:getLayout().maxVisible)
    self.scrollOffset = math.max(0, math.min(newOffset, maxOffset))
end

function ScrollableList:goToPage(pageNum, visible)
    local maxPage = self:getTotalPages(visible)
    pageNum = math.max(1, math.min(pageNum, maxPage))
    self.scrollOffset = (pageNum - 1) * self.pageSize
end

-- Show the list and wait for selection.
-- @return item, action  ("select" or "configure")   on success
--         nil, nil                                   on cancel/detach
function ScrollableList:show()
    local monitorName = peripheral.getName(self.monitor)

    while true do
        self.width, self.height = self.monitor.getSize()
        local visible = self:buildVisible()
        self:render()

        local kind, x, y = EventLoop.waitForMonitorEvent(monitorName)

        if kind == "detach" then
            return nil, nil
        elseif kind == "resize" then
            -- redraw on next iteration
        elseif kind == "touch" then
            local result = self:handleTouch(x, y, visible)

            if result == nil then
                -- no-op or group toggle (re-render)

            elseif result == ScrollableList.ACTION_CANCEL then
                return nil, nil

            elseif result == "scroll_up" then
                self:scrollBy(-1, visible)

            elseif result == "scroll_down" then
                self:scrollBy(1, visible)

            elseif result == "page_up" then
                self:goToPage(self:getCurrentPage() - 1, visible)

            elseif result == "page_down" then
                self:goToPage(self:getCurrentPage() + 1, visible)

            elseif type(result) == "table" then
                if result.action == "pending" then
                    -- Just re-render with highlight
                elseif result.action == ScrollableList.ACTION_SELECT then
                    return result.item, ScrollableList.ACTION_SELECT
                elseif result.action == ScrollableList.ACTION_CONFIGURE then
                    return result.item, ScrollableList.ACTION_CONFIGURE
                end

            elseif type(result) == "string" then
                -- Custom action from self.actions
                return result, nil
            end
        end
    end
end

-- Non-blocking render (for external event loops)
function ScrollableList:draw()
    self:render()
end

return ScrollableList
