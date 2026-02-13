-- EventUtils.lua
-- Safe event handling utilities for CC:Tweaked
-- Prevents event loss that occurs with os.pullEvent(filter) and os.sleep()
--
-- CRITICAL: os.pullEvent(filter) DISCARDS all non-matching events!
-- This module provides safe alternatives that preserve the event queue.

local EventUtils = {}

-- Internal: Pull event and requeue non-matching ones
-- @param filter Event type to wait for (or nil for any)
-- @param timeout Optional timeout in seconds
-- @return event data as multiple values, or nil if timeout
local function safePullEvent(filter, timeout)
    local timerId = nil
    if timeout then
        timerId = os.startTimer(timeout)
    end

    local events = {}

    while true do
        local event = {os.pullEventRaw()}

        -- Check for terminate
        if event[1] == "terminate" then
            -- Requeue saved events before terminating
            for _, e in ipairs(events) do
                os.queueEvent(table.unpack(e))
            end
            error("Terminated", 0)
        end

        -- Check for timeout
        if timerId and event[1] == "timer" and event[2] == timerId then
            -- Timeout reached, requeue saved events
            for _, e in ipairs(events) do
                os.queueEvent(table.unpack(e))
            end
            return nil
        end

        -- Check if this is the event we want
        if filter == nil or event[1] == filter then
            -- Found it! Requeue saved events and return
            for _, e in ipairs(events) do
                os.queueEvent(table.unpack(e))
            end
            -- Cancel timeout timer if set
            if timerId then
                os.cancelTimer(timerId)
            end
            return table.unpack(event)
        end

        -- Not the event we want, save it for later
        -- Don't save our own timeout timer events
        if not (timerId and event[1] == "timer" and event[2] == timerId) then
            table.insert(events, event)
        end
    end
end

-- Wait for a specific event type without discarding other events
-- @param filter Event type to wait for (e.g., "key", "monitor_touch")
-- @return event, p1, p2, p3, ... (same as os.pullEvent)
function EventUtils.pullEvent(filter)
    return safePullEvent(filter, nil)
end

-- Wait for a specific event type with timeout
-- @param filter Event type to wait for
-- @param timeout Timeout in seconds
-- @return event, p1, p2, p3, ... or nil if timeout
function EventUtils.pullEventTimeout(filter, timeout)
    return safePullEvent(filter, timeout)
end

-- Wait for key press without discarding other events
-- @return key code
function EventUtils.waitForKey()
    local event, key = safePullEvent("key", nil)
    return key
end

-- Wait for monitor touch without discarding other events
-- @param expectedSide Optional: only accept touches from this monitor
-- @return side, x, y
function EventUtils.waitForTouch(expectedSide)
    while true do
        local event, side, x, y = safePullEvent("monitor_touch", nil)
        if expectedSide == nil or side == expectedSide then
            return side, x, y
        end
        -- Wrong monitor, keep waiting (event already requeued by safePullEvent)
    end
end

-- Safe sleep that preserves events
-- @param seconds Time to sleep
function EventUtils.sleep(seconds)
    local timerId = os.startTimer(seconds)
    local events = {}

    while true do
        local event = {os.pullEventRaw()}

        if event[1] == "terminate" then
            for _, e in ipairs(events) do
                os.queueEvent(table.unpack(e))
            end
            error("Terminated", 0)
        end

        if event[1] == "timer" and event[2] == timerId then
            -- Sleep complete, requeue saved events
            for _, e in ipairs(events) do
                os.queueEvent(table.unpack(e))
            end
            return
        end

        -- Save non-timer events (or timer events that aren't ours)
        table.insert(events, event)
    end
end

return EventUtils
