-- ChangesDataHandler.lua
-- Data handling utilities for ChangesFactory
-- Snapshot taking, change calculation, and totals
-- Extracted from ChangesFactory.lua for maintainability

local Yield = mpm('utils/Yield')

local ChangesDataHandler = {}

-- Take a snapshot of current resource amounts
-- @param interface AE interface
-- @param dataMethod Method name to call (items/fluids/chemicals)
-- @param idField Field name for resource ID (registryName/name)
-- @param amountField Field name for amount (count/amount)
-- @return snapshot table, count, success
function ChangesDataHandler.takeSnapshot(interface, dataMethod, idField, amountField)
    if not interface then
        return {}, 0, false
    end

    local ok, resources = pcall(function() return interface[dataMethod](interface) end)
    if not ok or not resources then
        return {}, 0, false
    end

    Yield.yield()

    local snapshot = {}
    local count = 0

    for idx, resource in ipairs(resources) do
        local id = resource[idField]
        if id then
            local amount = resource[amountField] or resource.count or resource.amount or 0
            if amount > 0 then
                snapshot[id] = (snapshot[id] or 0) + amount
                count = count + 1
            end
        end
        if idx % 100 == 0 then
            Yield.yield()
        end
    end

    return snapshot, count, true
end

-- Deep copy a snapshot table
function ChangesDataHandler.copySnapshot(snapshot)
    local copy = {}
    for k, v in pairs(snapshot) do
        copy[k] = v
    end
    return copy
end

-- Calculate changes between baseline and current snapshots
-- @param baseline Previous snapshot
-- @param current Current snapshot
-- @param showMode "both", "gains", or "losses"
-- @param minChange Minimum change threshold
-- @return Array of change records {id, change, current, baseline}
function ChangesDataHandler.calculateChanges(baseline, current, showMode, minChange)
    local changes = {}

    if not baseline or not current then
        return changes
    end

    local seen = {}

    for id, currAmount in pairs(current) do
        seen[id] = true
        local baseAmount = baseline[id] or 0
        local change = currAmount - baseAmount

        if change ~= 0 and math.abs(change) >= minChange then
            local include = (showMode == "both") or
                (showMode == "gains" and change > 0) or
                (showMode == "losses" and change < 0)

            if include then
                table.insert(changes, {
                    id = id,
                    change = change,
                    current = currAmount,
                    baseline = baseAmount
                })
            end
        end
    end

    for id, baseAmount in pairs(baseline) do
        if not seen[id] and baseAmount > 0 then
            local change = -baseAmount
            if math.abs(change) >= minChange then
                local include = (showMode == "both") or (showMode == "losses")
                if include then
                    table.insert(changes, {
                        id = id,
                        change = change,
                        current = 0,
                        baseline = baseAmount
                    })
                end
            end
        end
    end

    return changes
end

-- Calculate summary totals from changes
-- @param changes Array of change records
-- @return gains, losses (both positive numbers)
function ChangesDataHandler.calculateTotals(changes)
    local gains, losses = 0, 0
    for _, resource in ipairs(changes) do
        if resource.change > 0 then
            gains = gains + resource.change
        else
            losses = losses + math.abs(resource.change)
        end
    end
    return gains, losses
end

-- Draw timer bar at bottom of screen
-- @param monitor Monitor to draw on
-- @param y Y position for bar
-- @param width Screen width
-- @param elapsed Elapsed time in seconds
-- @param total Total period in seconds
-- @param barColor Color for progress bar
function ChangesDataHandler.drawTimerBar(monitor, y, width, elapsed, total, barColor)
    local progress = math.min(1, elapsed / total)
    local remaining = math.max(0, total - elapsed)

    local timeStr
    if remaining >= 3600 then
        timeStr = string.format("%dh%dm", math.floor(remaining / 3600), math.floor((remaining % 3600) / 60))
    elseif remaining >= 60 then
        timeStr = string.format("%dm%ds", math.floor(remaining / 60), remaining % 60)
    else
        timeStr = remaining .. "s"
    end

    local barWidth = math.max(4, width - #timeStr - 3)
    local filledWidth = math.floor(barWidth * progress)
    local emptyWidth = barWidth - filledWidth

    monitor.setCursorPos(1, y)
    monitor.setBackgroundColor(colors.gray)
    monitor.setTextColor(colors.white)

    if filledWidth > 0 then
        monitor.setBackgroundColor(barColor)
        monitor.write(string.rep(" ", filledWidth))
    end

    if emptyWidth > 0 then
        monitor.setBackgroundColor(colors.gray)
        monitor.write(string.rep(" ", emptyWidth))
    end

    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.lightGray)
    monitor.setCursorPos(width - #timeStr + 1, y)
    monitor.write(timeStr)
end

return ChangesDataHandler
