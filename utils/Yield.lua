-- Yield.lua
-- Cooperative yielding utilities for CC:Tweaked
-- Prevents "too long without yielding" errors while preserving event queue

local Yield = {}

-- Default interval for batch processing
Yield.DEFAULT_INTERVAL = 100

-- Unique event name for yielding
local YIELD_EVENT = "mpm_yield"

-- Fast yield that preserves event queue
-- Unlike os.sleep(0), this is instant and doesn't discard events
-- Pattern: queue custom event, then pull it immediately
function Yield.yield()
    os.queueEvent(YIELD_EVENT)
    os.pullEvent(YIELD_EVENT)
end

-- Yield if counter reaches interval
-- @param counter Current iteration count
-- @param interval Yield every N iterations (default: 100)
-- @return true if yielded
function Yield.check(counter, interval)
    interval = interval or Yield.DEFAULT_INTERVAL
    if counter % interval == 0 then
        Yield.yield()
        return true
    end
    return false
end

-- Create a batch processor that auto-yields
-- @param interval Yield every N iterations
-- @return function(counter) that yields when needed
function Yield.batcher(interval)
    interval = interval or Yield.DEFAULT_INTERVAL
    return function(counter)
        return Yield.check(counter, interval)
    end
end

-- Process array with automatic yielding
-- @param array Array to process
-- @param callback Function(item, index) called for each item
-- @param interval Yield every N items (default: 100)
function Yield.forEach(array, callback, interval)
    interval = interval or Yield.DEFAULT_INTERVAL
    for i, item in ipairs(array) do
        callback(item, i)
        Yield.check(i, interval)
    end
end

-- Process table pairs with automatic yielding
-- @param tbl Table to process
-- @param callback Function(key, value, count) called for each pair
-- @param interval Yield every N items (default: 100)
function Yield.forPairs(tbl, callback, interval)
    interval = interval or Yield.DEFAULT_INTERVAL
    local count = 0
    for k, v in pairs(tbl) do
        count = count + 1
        callback(k, v, count)
        Yield.check(count, interval)
    end
    return count
end

-- Map array with automatic yielding
-- @param array Input array
-- @param transform Function(item, index) -> newItem
-- @param interval Yield every N items (default: 100)
-- @return New array with transformed items
function Yield.map(array, transform, interval)
    interval = interval or Yield.DEFAULT_INTERVAL
    local result = {}
    for i, item in ipairs(array) do
        result[i] = transform(item, i)
        Yield.check(i, interval)
    end
    return result
end

-- Filter array with automatic yielding
-- @param array Input array
-- @param predicate Function(item, index) -> boolean
-- @param interval Yield every N items (default: 100)
-- @return New array with items where predicate returned true
function Yield.filter(array, predicate, interval)
    interval = interval or Yield.DEFAULT_INTERVAL
    local result = {}
    for i, item in ipairs(array) do
        if predicate(item, i) then
            table.insert(result, item)
        end
        Yield.check(i, interval)
    end
    return result
end

return Yield
