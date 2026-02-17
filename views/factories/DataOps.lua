-- DataOps.lua
-- Shared sorting/filtering/aggregation helpers for factory views

local DataOps = {}

local function getName(item, idField)
    return item.displayName or item.registryName or item[idField] or ""
end

function DataOps.sortByAmountOrName(items, sortBy, amountField, sortField, idField)
    if sortBy == sortField or sortBy == "amount" or sortBy == "count" then
        table.sort(items, function(a, b)
            return (a[amountField] or 0) > (b[amountField] or 0)
        end)
        return
    end

    if sortBy == sortField .. "_asc" or sortBy == "amount_asc" or sortBy == "count_asc" then
        table.sort(items, function(a, b)
            return (a[amountField] or 0) < (b[amountField] or 0)
        end)
        return
    end

    if sortBy == "name" then
        table.sort(items, function(a, b)
            return getName(a, idField) < getName(b, idField)
        end)
    end
end

function DataOps.filterByMin(items, amountField, minRaw)
    if (minRaw or 0) <= 0 then
        return items
    end

    local filtered = {}
    for _, item in ipairs(items) do
        if (item[amountField] or 0) >= minRaw then
            table.insert(filtered, item)
        end
    end
    return filtered
end

function DataOps.totalByAmount(items, amountField, divisor)
    local total = 0
    for _, item in ipairs(items) do
        total = total + ((item[amountField] or 0) / divisor)
    end
    return total
end

return DataOps
