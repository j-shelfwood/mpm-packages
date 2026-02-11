-- Notifications.lua
-- Notification storage and display for pocket computer

local Notifications = {}
Notifications.__index = Notifications

-- Maximum notifications to keep
local MAX_NOTIFICATIONS = 50

-- Create new notification manager
function Notifications.new()
    local self = setmetatable({}, Notifications)
    self.notifications = {}

    return self
end

-- Add a notification
-- @param level Level: info, warning, error, critical
-- @param title Notification title
-- @param message Notification message
function Notifications:add(level, title, message)
    table.insert(self.notifications, 1, {
        level = level,
        title = title,
        message = message,
        timestamp = os.epoch("utc"),
        read = false
    })

    -- Trim if too many
    while #self.notifications > MAX_NOTIFICATIONS do
        table.remove(self.notifications)
    end
end

-- Get all notifications
function Notifications:getAll()
    return self.notifications
end

-- Get unread notifications
function Notifications:getUnread()
    local unread = {}
    for _, note in ipairs(self.notifications) do
        if not note.read then
            table.insert(unread, note)
        end
    end
    return unread
end

-- Mark all as read
function Notifications:markAllRead()
    for _, note in ipairs(self.notifications) do
        note.read = true
    end
end

-- Clear all notifications
function Notifications:clear()
    self.notifications = {}
end

-- Get count
function Notifications:count()
    return #self.notifications
end

-- Get unread count
function Notifications:unreadCount()
    local count = 0
    for _, note in ipairs(self.notifications) do
        if not note.read then
            count = count + 1
        end
    end
    return count
end

-- Show a brief notification on screen
function Notifications:notify(title, message)
    -- Play sound if available
    -- (Would need speaker peripheral)

    -- Flash the screen briefly
    local oldBg = term.getBackgroundColor()
    term.setBackgroundColor(colors.blue)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.white)
    print("")
    print("  " .. title)
    term.setTextColor(colors.lightGray)
    print("  " .. (message or ""):sub(1, 20))
    sleep(0.5)
    term.setBackgroundColor(oldBg)
end

return Notifications
