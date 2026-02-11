-- Touch.lua
-- Touch event routing and handling

local Touch = {}

-- Touch event state
local touchState = {
    lastTouch = nil,
    lastTime = 0,
    doubleTapThreshold = 500  -- milliseconds
}

-- Check if this is a double tap
function Touch.isDoubleTap(x, y)
    local now = os.epoch("utc")

    if touchState.lastTouch then
        local dx = math.abs(x - touchState.lastTouch.x)
        local dy = math.abs(y - touchState.lastTouch.y)
        local dt = now - touchState.lastTime

        if dx <= 1 and dy <= 1 and dt < touchState.doubleTapThreshold then
            touchState.lastTouch = nil
            return true
        end
    end

    touchState.lastTouch = {x = x, y = y}
    touchState.lastTime = now
    return false
end

-- Determine touch region (for simple layout)
-- @param x, y Touch coordinates
-- @param width, height Screen dimensions
-- @return region name: "left", "right", "top", "bottom", "center"
function Touch.getRegion(x, y, width, height)
    local thirdW = width / 3
    local thirdH = height / 3

    if y <= thirdH then
        return "top"
    elseif y >= height - thirdH then
        return "bottom"
    elseif x <= thirdW then
        return "left"
    elseif x >= width - thirdW then
        return "right"
    else
        return "center"
    end
end

-- Check if touch is in navigation area (sides)
function Touch.isNavigation(x, width)
    local half = width / 2
    if x <= half then
        return "prev"
    else
        return "next"
    end
end

-- Check if touch is in config area (bottom)
function Touch.isConfigArea(y, height)
    return y == height
end

-- Wait for a touch event on a specific monitor
-- @param monitorName Monitor to listen for
-- @param timeout Timeout in seconds (nil = forever)
-- @return x, y or nil on timeout
function Touch.waitForTouch(monitorName, timeout)
    local timer = nil
    if timeout then
        timer = os.startTimer(timeout)
    end

    while true do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "monitor_touch" and p1 == monitorName then
            if timer then
                os.cancelTimer(timer)
            end
            return p2, p3
        elseif event == "timer" and p1 == timer then
            return nil, nil
        end
    end
end

-- Wait for touch in a specific region
-- @param monitor Monitor peripheral
-- @param regions Table of region names to accept
-- @param timeout Timeout in seconds
-- @return region name or nil
function Touch.waitForRegion(monitor, regions, timeout)
    local monitorName = peripheral.getName(monitor)
    local width, height = monitor.getSize()

    local x, y = Touch.waitForTouch(monitorName, timeout)
    if not x then
        return nil
    end

    local region = Touch.getRegion(x, y, width, height)

    for _, r in ipairs(regions) do
        if r == region then
            return region, x, y
        end
    end

    return nil, x, y
end

-- Create a touch handler that routes to callbacks
-- @param monitor Monitor peripheral
-- @param callbacks Table of region -> function mappings
-- @return handler function
function Touch.createHandler(monitor, callbacks)
    local monitorName = peripheral.getName(monitor)
    local width, height = monitor.getSize()

    return function(eventMonitor, x, y)
        if eventMonitor ~= monitorName then
            return false
        end

        local region = Touch.getRegion(x, y, width, height)
        local callback = callbacks[region]

        if callback then
            callback(x, y)
            return true
        end

        return false
    end
end

return Touch
