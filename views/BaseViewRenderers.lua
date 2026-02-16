-- BaseViewRenderers.lua
-- Rendering helpers for BaseView framework
-- Handles header, footer, grid, list, and interactive list rendering
-- Extracted from BaseView.lua for maintainability

local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local GridDisplay = mpm('utils/GridDisplay')

local BaseViewRenderers = {}

-- Default empty state renderer
function BaseViewRenderers.renderEmpty(self, message)
    message = message or "No data"
    MonitorHelpers.writeCentered(
        self.monitor,
        math.floor(self.height / 2),
        message,
        colors.gray
    )
end

-- Default error state renderer
function BaseViewRenderers.renderError(self, message)
    MonitorHelpers.writeCentered(
        self.monitor,
        math.floor(self.height / 2),
        message or "Error",
        colors.red
    )
end

-- Render header at top of screen
-- Header row is touchable to open view selector (indicated by [*])
-- @return startY for content
function BaseViewRenderers.renderHeader(self, header)
    if not header then return 1 end

    -- Reserve space for [*] indicator (3 chars)
    local indicatorWidth = 3
    local contentWidth = self.width - indicatorWidth

    self.monitor.setCursorPos(1, 1)

    if type(header) == "string" then
        self.monitor.setTextColor(colors.white)
        self.monitor.write(Text.truncateMiddle(header, contentWidth))
    elseif type(header) == "table" then
        -- Primary text
        self.monitor.setTextColor(header.color or colors.white)
        local text = header.text or ""
        self.monitor.write(text)

        -- Secondary text (count, etc.)
        if header.secondary then
            self.monitor.setTextColor(header.secondaryColor or colors.gray)
            local remaining = contentWidth - #text
            if remaining > 0 then
                self.monitor.write(Text.truncateMiddle(header.secondary, remaining))
            end
        end
    end

    -- Draw [*] indicator at end of header row to show it's touchable
    self.monitor.setCursorPos(self.width - 2, 1)
    self.monitor.setTextColor(colors.gray)
    self.monitor.write("[*]")

    return 2  -- Content starts at row 2
end

-- Render footer at bottom of screen
function BaseViewRenderers.renderFooter(self, footer)
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

-- Compact list threshold: monitors narrower than this use single-line list mode
local COMPACT_LIST_THRESHOLD = 20

-- Render compact single-line list for narrow monitors
-- Each item: "Name         Count" on one line (name left, count right)
local function renderCompactList(self, data, formatItem, startY, def)
    local maxItems = def.maxItems or 50
    local maxRows = self.height - startY
    local count = math.min(#data, maxItems, maxRows)

    for i = 1, count do
        local item = data[i]
        local y = startY + i - 1
        if y > self.height - 1 then break end  -- Leave room for footer

        local formatted = formatItem(self, item)
        if formatted.lines then
            local name = formatted.lines[1] or ""
            local amount = formatted.lines[2] or ""
            local nameColor = formatted.colors and formatted.colors[1] or colors.white
            local amountColor = formatted.colors and formatted.colors[2] or colors.gray

            -- Calculate widths: reserve space for amount + 1 gap char
            local amountWidth = #amount
            local nameWidth = self.width - amountWidth - 1
            if nameWidth < 1 then nameWidth = self.width end

            -- Truncate name to fit, preserving readable prefix
            local displayName = Text.truncateEnd(name, nameWidth)

            -- Write name (left-aligned)
            self.monitor.setCursorPos(1, y)
            self.monitor.setTextColor(nameColor)
            self.monitor.write(displayName)

            -- Write amount (right-aligned)
            if amountWidth > 0 and self.width > amountWidth then
                local amountX = self.width - amountWidth + 1
                self.monitor.setCursorPos(amountX, y)
                self.monitor.setTextColor(amountColor)
                self.monitor.write(amount)
            end
        end
    end

    -- Show overflow indicator
    if #data > count then
        self.monitor.setCursorPos(1, self.height)
        self.monitor.setTextColor(colors.gray)
        self.monitor.write("+" .. (#data - count) .. " more")
    end
end

-- Render grid layout
function BaseViewRenderers.renderGrid(self, data, formatItem, startY, def)
    -- Auto-switch to compact list mode on narrow monitors
    -- Narrow monitors can't fit readable grid cells; single-line list is clearer
    if self.width < COMPACT_LIST_THRESHOLD then
        renderCompactList(self, data, formatItem, startY, def)
        return
    end

    if not self._gridDisplay then
        self._gridDisplay = GridDisplay.new(self.monitor, {
            cellHeight = def.cellHeight or 2,
            gap = { x = def.gapX or 1, y = def.gapY or 0 },
            headerRows = (startY or 1) - 1,
            columns = def.columns,
            minCellWidth = def.minCellWidth or 16,
        })
    end

    -- Limit items for performance
    local maxItems = def.maxItems or 50
    local displayData = {}
    for i = 1, math.min(#data, maxItems) do
        displayData[i] = data[i]
    end

    -- Calculate layout and render
    self._gridDisplay:layout(#displayData)
    self._gridDisplay:render(displayData, function(item)
        return formatItem(self, item)
    end)
end

-- Render list layout
function BaseViewRenderers.renderList(self, data, formatItem, startY, def)
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
function BaseViewRenderers.renderInteractiveList(self, data, formatItem, startY, def)
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

-- Handle touch for interactive views
-- @return true if touch was handled
function BaseViewRenderers.handleInteractiveTouch(self, x, y, onItemTouch)
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
        if onItemTouch then
            onItemTouch(self, zone.item, zone.action)
            return true
        end
    end

    return false
end

return BaseViewRenderers
