-- ItemDetail.lua
-- Modal overlay showing full item details with action buttons
-- For use in interactive views (CraftableBrowser, ItemBrowser, etc.)
-- Uses os.pullEvent directly - each monitor runs in its own coroutine with parallel API

local Core = mpm('ui/Core')
local Text = mpm('utils/Text')

local ItemDetail = {}
ItemDetail.__index = ItemDetail

-- Create a new item detail overlay
-- @param monitor Monitor peripheral
-- @param item Item table with at least {displayName or registryName}
-- @param opts Configuration table:
--   showCraftButton: Show [Craft] button (default: true if item.isCraftable)
--   showCount: Show item count (default: true)
--   showRegistryName: Show full registry name (default: true)
--   craftAmount: Default craft amount (default: 1)
--   actions: Additional {label, action} buttons
-- @return ItemDetail instance
function ItemDetail.new(monitor, item, opts)
    local self = setmetatable({}, ItemDetail)

    self.monitor = monitor
    self.item = item or {}
    opts = opts or {}

    self.showCraftButton = opts.showCraftButton
    if self.showCraftButton == nil then
        self.showCraftButton = item.isCraftable == true
    end

    self.showCount = opts.showCount ~= false
    self.showRegistryName = opts.showRegistryName ~= false
    self.craftAmount = opts.craftAmount or 1
    self.additionalActions = opts.actions or {}

    self.width, self.height = monitor.getSize()

    -- Button zones (populated during render)
    self.buttons = {}

    return self
end

-- Calculate overlay bounds (centered)
function ItemDetail:calculateBounds()
    -- Content lines: name, count, registry name, spacer
    local contentLines = 2  -- name + spacer before buttons
    if self.showCount then contentLines = contentLines + 1 end
    if self.showRegistryName then contentLines = contentLines + 1 end

    local overlayWidth = math.min(self.width - 2, 30)
    local overlayHeight = contentLines + 4  -- content + header + footer + padding

    local x1 = math.floor((self.width - overlayWidth) / 2) + 1
    local y1 = math.floor((self.height - overlayHeight) / 2) + 1
    local x2 = x1 + overlayWidth - 1
    local y2 = y1 + overlayHeight - 1

    return x1, y1, x2, y2
end

-- Render the overlay
function ItemDetail:render()
    local x1, y1, x2, y2 = self:calculateBounds()
    local overlayWidth = x2 - x1 + 1
    local contentX = x1 + 1
    local contentWidth = overlayWidth - 2

    -- Draw background
    self.monitor.setBackgroundColor(colors.gray)
    for y = y1, y2 do
        self.monitor.setCursorPos(x1, y)
        self.monitor.write(string.rep(" ", overlayWidth))
    end

    -- Draw title bar
    local title = "Item Details"
    self.monitor.setBackgroundColor(colors.lightGray)
    self.monitor.setTextColor(colors.black)
    self.monitor.setCursorPos(x1, y1)
    self.monitor.write(string.rep(" ", overlayWidth))
    local titleX = x1 + math.floor((overlayWidth - #title) / 2)
    self.monitor.setCursorPos(titleX, y1)
    self.monitor.write(title)

    -- Draw content
    self.monitor.setBackgroundColor(colors.gray)
    local contentY = y1 + 2

    -- Item display name
    local displayName = self.item.displayName or Text.prettifyName(self.item.registryName or "Unknown")
    self.monitor.setTextColor(colors.white)
    self.monitor.setCursorPos(contentX, contentY)
    self.monitor.write(Core.truncate(displayName, contentWidth))
    contentY = contentY + 1

    -- Item count
    if self.showCount then
        local count = self.item.count or self.item.amount or 0
        local countText = "Stock: " .. Text.formatNumber(count)
        local countColor = colors.lime
        if count == 0 then
            countColor = colors.red
        elseif count < 64 then
            countColor = colors.orange
        end
        self.monitor.setTextColor(countColor)
        self.monitor.setCursorPos(contentX, contentY)
        self.monitor.write(countText)
        contentY = contentY + 1
    end

    -- Registry name (smaller, grayed)
    if self.showRegistryName and self.item.registryName then
        self.monitor.setTextColor(colors.lightGray)
        self.monitor.setCursorPos(contentX, contentY)
        self.monitor.write(Core.truncate(self.item.registryName, contentWidth))
        contentY = contentY + 1
    end

    -- Draw buttons
    self:renderButtons(x1, y2 - 1, overlayWidth)

    Core.resetColors(self.monitor)
end

-- Render action buttons
function ItemDetail:renderButtons(x1, y, overlayWidth)
    self.buttons = {}

    local buttonList = {}

    -- Craft button
    if self.showCraftButton then
        table.insert(buttonList, { label = "[Craft]", action = "craft", color = colors.lime })
    end

    -- Additional actions
    for _, action in ipairs(self.additionalActions) do
        table.insert(buttonList, { label = action.label, action = action.action, color = action.color or colors.cyan })
    end

    -- Close button
    table.insert(buttonList, { label = "[Close]", action = "close", color = colors.red })

    -- Calculate total width and starting position
    local totalWidth = 0
    for _, btn in ipairs(buttonList) do
        totalWidth = totalWidth + #btn.label + 1
    end

    local startX = x1 + math.floor((overlayWidth - totalWidth) / 2)
    local x = startX

    for _, btn in ipairs(buttonList) do
        local btnWidth = #btn.label

        -- Store button zone
        self.buttons[btn.action] = {
            x1 = x,
            x2 = x + btnWidth - 1,
            y = y
        }

        -- Draw button
        self.monitor.setBackgroundColor(colors.gray)
        self.monitor.setTextColor(btn.color)
        self.monitor.setCursorPos(x, y)
        self.monitor.write(btn.label)

        x = x + btnWidth + 1
    end
end

-- Handle touch event
-- @return "craft", "close", action string, or nil
function ItemDetail:handleTouch(x, y)
    for action, zone in pairs(self.buttons) do
        if y == zone.y and x >= zone.x1 and x <= zone.x2 then
            return action
        end
    end

    -- Touch outside overlay = close
    local ox1, oy1, ox2, oy2 = self:calculateBounds()
    if x < ox1 or x > ox2 or y < oy1 or y > oy2 then
        return "close"
    end

    return nil
end

-- Show the overlay and wait for action
-- @return "craft", "close", or custom action string
function ItemDetail:show()
    local monitorName = peripheral.getName(self.monitor)

    while true do
        self:render()

        local side, x, y
        repeat
            local _, touchSide, tx, ty = os.pullEvent("monitor_touch")
            side, x, y = touchSide, tx, ty
        until side == monitorName

        if side == monitorName then
            local result = self:handleTouch(x, y)

            if result then
                return result
            end
        end
    end
end

-- Get the item being displayed
function ItemDetail:getItem()
    return self.item
end

-- Update the item (for refreshing after craft)
function ItemDetail:setItem(item)
    self.item = item or {}
end

return ItemDetail
