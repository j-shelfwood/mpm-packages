-- TimerDispatch.lua
-- Global timer dispatcher for UI blocking loops
--
-- Problem: When UI components block with event loops (List:show(), ConfigUI),
-- timer events for other monitors get trapped and never processed.
--
-- Solution: UI loops use os.pullEvent() without filter and dispatch timer
-- events through this module, which forwards them to registered monitors.

local TimerDispatch = {
    monitors = nil,
    enabled = false
}

-- Set up dispatcher with monitor list
-- @param monitors Array of Monitor instances with handleTimer(timerId) method
function TimerDispatch.setup(monitors)
    TimerDispatch.monitors = monitors
    TimerDispatch.enabled = true
end

-- Clear dispatcher (call after blocking UI completes)
function TimerDispatch.clear()
    TimerDispatch.monitors = nil
    TimerDispatch.enabled = false
end

-- Dispatch a timer event to all monitors
-- @param timerId The timer ID from the timer event
-- @return true if any monitor handled it
function TimerDispatch.dispatch(timerId)
    if not TimerDispatch.enabled or not TimerDispatch.monitors then
        return false
    end

    local handled = false
    for _, monitor in ipairs(TimerDispatch.monitors) do
        if monitor.handleTimer and monitor:handleTimer(timerId) then
            handled = true
        end
    end
    return handled
end

-- Pull event and auto-dispatch timers
-- Use this instead of EventUtils.pullEvent in blocking UI loops
-- @param filter Event type to wait for (e.g., "monitor_touch")
-- @return event, p1, p2, p3, ... when filter matches
function TimerDispatch.pullEvent(filter)
    while true do
        local event = {os.pullEvent()}

        if event[1] == "timer" then
            -- Dispatch timer to monitors, then continue waiting
            TimerDispatch.dispatch(event[2])
        elseif filter == nil or event[1] == filter then
            -- This is the event we want
            return table.unpack(event)
        end
        -- Other events (key, char, etc.) are discarded while UI is blocking
        -- This is acceptable for modal UI that only cares about touches
    end
end

return TimerDispatch
