-- EventLoop.lua
-- Shared event loop helpers for mixed key + monitor touch input flows

local EventUtils = mpm('utils/EventUtils')

local EventLoop = {}

-- Wait for a monitor touch, optionally limited to a specific monitor name.
-- @param monitorName Optional peripheral name
-- @return side, x, y
function EventLoop.waitForMonitorTouch(monitorName)
    while true do
        local _, side, x, y = EventUtils.pullEvent("monitor_touch")
        if monitorName == nil or side == monitorName then
            return side, x, y
        end
    end
end

-- Wait for either a key or matching monitor touch.
-- @param monitorName Optional peripheral name
-- @return kind ("key"|"touch"), p1, p2, p3
--   key:   p1 = keyCode
--   touch: p1 = x, p2 = y, p3 = side
function EventLoop.waitForTouchOrKey(monitorName)
    while true do
        local event, p1, p2, p3 = EventUtils.pullEvent()

        if event == "key" then
            return "key", p1
        end

        if event == "monitor_touch" and (monitorName == nil or p1 == monitorName) then
            return "touch", p2, p3, p1
        end
    end
end

-- Wait for a key press.
-- @return keyCode
function EventLoop.waitForKey()
    local _, keyCode = EventUtils.pullEvent("key")
    return keyCode
end

return EventLoop
