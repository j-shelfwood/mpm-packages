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
    enabled = false,
    debug = false  -- Set to true for diagnostic output
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
        if TimerDispatch.debug then
            print("[TD] dispatch(" .. tostring(timerId) .. ") - not enabled or no monitors")
        end
        return false
    end

    if TimerDispatch.debug then
        print("[TD] dispatch(" .. tostring(timerId) .. ") to " .. #TimerDispatch.monitors .. " monitors")
    end

    local handled = false
    for i, monitor in ipairs(TimerDispatch.monitors) do
        if monitor.handleTimer then
            local result = monitor:handleTimer(timerId)
            if TimerDispatch.debug then
                local name = monitor.peripheralName or ("mon" .. i)
                local rt = monitor.renderTimer or "nil"
                print("[TD]   " .. name .. " rt=" .. tostring(rt) .. " -> " .. tostring(result))
            end
            if result then
                handled = true
            end
        end
    end
    return handled
end

-- Pull event and auto-dispatch timers
-- Use this instead of EventUtils.pullEvent in blocking UI loops
-- @param filter Event type to wait for (e.g., "monitor_touch")
-- @return event, p1, p2, p3, ... when filter matches
function TimerDispatch.pullEvent(filter)
    if TimerDispatch.debug then
        print("[TD] pullEvent(" .. tostring(filter) .. ") started")
    end

    while true do
        local event = {os.pullEvent()}

        if event[1] == "timer" then
            -- Dispatch timer to monitors, then continue waiting
            if TimerDispatch.debug then
                print("[TD] got timer(" .. tostring(event[2]) .. ")")
            end
            TimerDispatch.dispatch(event[2])
        elseif filter == nil or event[1] == filter then
            -- This is the event we want
            if TimerDispatch.debug then
                print("[TD] returning " .. tostring(event[1]))
            end
            return table.unpack(event)
        else
            if TimerDispatch.debug then
                print("[TD] ignoring " .. tostring(event[1]))
            end
        end
        -- Other events (key, char, etc.) are discarded while UI is blocking
        -- This is acceptable for modal UI that only cares about touches
    end
end

return TimerDispatch
