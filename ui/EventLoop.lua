-- EventLoop.lua
-- Shared event loop helpers for mixed key + monitor touch input flows


local EventLoop = {}
local TOUCH_GUARD_UNTIL = {}
local DRAIN_EVENT_PREFIX = "mpm_touch_drain_" .. tostring(os.epoch("utc")) .. "_"
local drainCounter = 0

local function nowMs()
    return os.epoch("utc")
end

local function isTouchGuarded(side)
    if not side then
        return false
    end
    local untilMs = TOUCH_GUARD_UNTIL[side]
    if not untilMs then
        return false
    end
    if nowMs() >= untilMs then
        TOUCH_GUARD_UNTIL[side] = nil
        return false
    end
    return true
end

-- Ignore monitor touches from this monitor for a short window.
-- Useful after modal transitions to prevent queued burst touches from re-triggering UI.
-- @param monitorName Peripheral name
-- @param durationMs Guard window in milliseconds
function EventLoop.armTouchGuard(monitorName, durationMs)
    if not monitorName then
        return
    end
    local ms = tonumber(durationMs) or 0
    if ms <= 0 then
        TOUCH_GUARD_UNTIL[monitorName] = nil
        return
    end
    TOUCH_GUARD_UNTIL[monitorName] = nowMs() + ms
end

-- Drain queued monitor_touch events for a specific monitor (or all monitors).
-- This preserves all non-touch events and touches for other monitors.
-- @param monitorName Optional peripheral name
-- @param maxDrain Optional cap on dropped touch events
-- @return drainedCount
function EventLoop.drainMonitorTouches(monitorName, maxDrain)
    local limit = tonumber(maxDrain) or math.huge
    if limit <= 0 then
        return 0
    end

    drainCounter = drainCounter + 1
    local marker = DRAIN_EVENT_PREFIX .. tostring(drainCounter)
    local retained = {}
    local drained = 0

    os.queueEvent(marker)

    while true do
        local event = { os.pullEventRaw() }
        if event[1] == marker then
            break
        elseif event[1] == "terminate" then
            for i = 1, #retained do
                os.queueEvent(table.unpack(retained[i]))
            end
            error("Terminated", 0)
        end

        local isTargetTouch = event[1] == "monitor_touch" and (monitorName == nil or event[2] == monitorName)
        if isTargetTouch and drained < limit then
            drained = drained + 1
        else
            table.insert(retained, event)
        end
    end

    for i = 1, #retained do
        os.queueEvent(table.unpack(retained[i]))
    end

    return drained
end

-- Wait for monitor-related events for a specific monitor (or any monitor).
-- @param monitorName Optional peripheral name
-- @param opts Optional table:
--   acceptAnyWhenNil (boolean): when true and monitorName=nil, accept touches from any monitor
--   acceptKey (boolean): return key events
--   acceptTermResize (boolean): return term_resize events
-- @return kind, p1, p2, p3
--   touch:  p1=x, p2=y, p3=side
--   resize: p1=side (for monitor_resize) or nil (for term_resize)
--   detach: p1=side
--   key:    p1=keyCode
function EventLoop.waitForMonitorEvent(monitorName, opts)
    opts = opts or {}
    local acceptAnyWhenNil = opts.acceptAnyWhenNil == true
    local acceptKey = opts.acceptKey == true
    local acceptTermResize = opts.acceptTermResize == true

    while true do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "monitor_touch" then
            if isTouchGuarded(p1) then
                goto continue
            end
            if monitorName and p1 == monitorName then
                return "touch", p2, p3, p1
            end
            if monitorName == nil and acceptAnyWhenNil then
                return "touch", p2, p3, p1
            end
        elseif event == "monitor_resize" then
            if monitorName == nil or p1 == monitorName then
                return "resize", p1
            end
        elseif event == "peripheral_detach" then
            if monitorName and p1 == monitorName then
                return "detach", p1
            end
        elseif event == "key" and acceptKey then
            return "key", p1
        elseif event == "term_resize" and acceptTermResize then
            return "resize", nil
        end
        ::continue::
    end
end

-- Wait for a monitor touch, optionally limited to a specific monitor name.
-- @param monitorName Optional peripheral name
-- @return side, x, y
function EventLoop.waitForMonitorTouch(monitorName)
    while true do
        local kind, x, y, side = EventLoop.waitForMonitorEvent(monitorName, {
            acceptAnyWhenNil = monitorName == nil
        })
        if kind == "touch" then
            return side, x, y
        elseif kind == "detach" then
            return nil, nil, nil, "detach"
        elseif kind == "resize" then
            return nil, nil, nil, "resize"
        end
    end
end

-- Wait for either a key or matching monitor touch.
-- @param monitorName Optional peripheral name
-- @param allowAnyMonitorTouch Optional boolean; when true and monitorName is nil,
--        monitor touches from any monitor are accepted.
-- @return kind ("key"|"touch"), p1, p2, p3
--   key:   p1 = keyCode
--   touch: p1 = x, p2 = y, p3 = side
function EventLoop.waitForTouchOrKey(monitorName, allowAnyMonitorTouch)
    while true do
        local kind, p1, p2, p3 = EventLoop.waitForMonitorEvent(monitorName, {
            acceptAnyWhenNil = allowAnyMonitorTouch == true,
            acceptKey = true,
            acceptTermResize = true
        })

        if kind == "key" then
            return "key", p1
        end
        if kind == "touch" then
            return "touch", p1, p2, p3
        end
        if kind == "resize" then
            return "resize"
        end
        if kind == "detach" then
            return "detach", p1
        end
    end
end

-- Wait for a key press.
-- @return keyCode
function EventLoop.waitForKey()
    while true do
        local event, keyCode = os.pullEvent()
        if event == "key" then
            return keyCode
        end
    end
end

return EventLoop
