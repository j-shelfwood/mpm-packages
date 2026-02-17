-- SchemaFragments.lua
-- Shared config-schema fragments for view factories

local SchemaFragments = {}

function SchemaFragments.warningBelow(defaultValue, unitLabel, presets)
    return {
        key = "warningBelow",
        type = "number",
        label = "Warning Below" .. (unitLabel ~= "" and " (" .. unitLabel .. ")" or ""),
        default = defaultValue,
        min = 1,
        max = 100000,
        presets = presets
    }
end

function SchemaFragments.sortByAmountOrName(sortField, includeAscending)
    local amountLabel = sortField == "count" and "Count" or "Amount"
    local options = {
        { value = sortField, label = includeAscending and (amountLabel .. " (High)") or amountLabel }
    }

    if includeAscending then
        table.insert(options, { value = sortField .. "_asc", label = amountLabel .. " (Low)" })
        table.insert(options, { value = "name", label = "Name (A-Z)" })
    else
        table.insert(options, { value = "name", label = "Name" })
    end

    return {
        key = "sortBy",
        type = "select",
        label = "Sort By",
        options = options,
        default = sortField
    }
end

function SchemaFragments.minFilter(unitLabel)
    local minKey = unitLabel == "B" and "minBuckets" or "minCount"
    local minLabel = unitLabel == "B" and "Min Buckets" or "Min Count"
    local minPresets = unitLabel == "B" and {0, 1, 10, 100, 1000} or {0, 1, 64, 1000}

    return {
        key = minKey,
        type = "number",
        label = minLabel,
        default = 0,
        min = 0,
        max = 100000,
        presets = minPresets
    }, minKey
end

function SchemaFragments.periodSampleMinChange(defaultMinChange, unitDivisor)
    return {
        {
            key = "periodSeconds",
            type = "number",
            label = "Reset Period (sec)",
            default = 60,
            min = 10,
            max = 86400,
            presets = {30, 60, 300, 600, 1800}
        },
        {
            key = "sampleSeconds",
            type = "number",
            label = "Sample Every (sec)",
            default = 5,
            min = 1,
            max = 60,
            presets = {1, 3, 5, 10, 30}
        },
        {
            key = "showMode",
            type = "select",
            label = "Show Changes",
            options = {
                { value = "both", label = "Gains & Losses" },
                { value = "gains", label = "Gains Only" },
                { value = "losses", label = "Losses Only" }
            },
            default = "both"
        },
        {
            key = "minChange",
            type = "number",
            label = "Min Change",
            default = defaultMinChange,
            min = 1,
            max = 100000,
            presets = unitDivisor > 1 and {100, 1000, 5000, 10000} or {1, 10, 50, 100}
        }
    }
end

return SchemaFragments
