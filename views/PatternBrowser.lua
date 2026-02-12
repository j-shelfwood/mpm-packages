-- PatternBrowser.lua
-- Displays all crafting patterns in the ME network
-- Shows pattern outputs, inputs, and type (crafting/processing/etc.)
--
-- Pattern structure from ME Bridge:
-- {
--   inputs = {
--     { primaryInput = {name, displayName, count}, possibleInputs = {...}, multiplier, remaining }
--   },
--   outputs = { {name, displayName, count}, ... },
--   primaryOutput = {name, displayName, count},
--   patternType = "crafting" | "processing" | "smithing" | "stonecutting"
-- }

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')

-- Helper functions
local function getDisplayName(pattern)
    if pattern.primaryOutput and pattern.primaryOutput.displayName then
        return pattern.primaryOutput.displayName
    elseif pattern.outputs and #pattern.outputs > 0 and pattern.outputs[1].displayName then
        return pattern.outputs[1].displayName
    end
    return "Unknown"
end

local function countInputs(pattern)
    if not pattern.inputs then return 0 end
    return #pattern.inputs
end

local function getPatternTypeColor(patternType)
    if patternType == "crafting" then
        return colors.lime
    elseif patternType == "processing" then
        return colors.lightBlue
    elseif patternType == "smithing" then
        return colors.orange
    elseif patternType == "stonecutting" then
        return colors.gray
    else
        return colors.white
    end
end

return BaseView.grid({
    sleepTime = 10,

    configSchema = {
        {
            key = "sortBy",
            type = "select",
            label = "Sort By",
            options = {
                { value = "output", label = "Output Name" },
                { value = "inputs", label = "Input Count" }
            },
            default = "output"
        },
        {
            key = "maxDisplay",
            type = "number",
            label = "Max Items",
            default = 50,
            min = 10,
            max = 200,
            presets = {25, 50, 100}
        }
    },

    mount = function()
        return AEInterface.exists()
    end,

    init = function(self, config)
        self.interface = AEInterface.new()
        self.sortBy = config.sortBy or "output"
        self.maxDisplay = config.maxDisplay or 50
        self.totalPatterns = 0  -- Will be set in getData
    end,

    getData = function(self)
        -- Get all patterns
        local patterns = self.interface.bridge.getPatterns()
        if not patterns then return {} end

        self.totalPatterns = #patterns

        -- Sort patterns
        if self.sortBy == "output" then
            table.sort(patterns, function(a, b)
                local nameA = getDisplayName(a)
                local nameB = getDisplayName(b)
                return nameA < nameB
            end)
        elseif self.sortBy == "inputs" then
            table.sort(patterns, function(a, b)
                local countA = countInputs(a)
                local countB = countInputs(b)
                if countA == countB then
                    return getDisplayName(a) < getDisplayName(b)
                end
                return countA > countB
            end)
        end

        -- Limit display
        local displayPatterns = {}
        for i = 1, math.min(#patterns, self.maxDisplay) do
            displayPatterns[i] = patterns[i]
        end

        return displayPatterns
    end,

    header = function(self, data)
        return {
            text = "PATTERNS",
            color = colors.cyan,
            secondary = " (" .. self.totalPatterns .. " total)",
            secondaryColor = colors.gray
        }
    end,

    formatItem = function(self, pattern)
        local displayName = getDisplayName(pattern)
        local inputCount = countInputs(pattern)
        local patternType = pattern.patternType or "unknown"
        local typeColor = getPatternTypeColor(patternType)

        return {
            lines = {
                displayName,
                inputCount .. " input" .. (inputCount ~= 1 and "s" or ""),
                "[" .. (patternType:sub(1, 1):upper() .. patternType:sub(2)) .. "]"
            },
            colors = {
                colors.white,
                colors.gray,
                typeColor
            }
        }
    end,

    emptyMessage = "No crafting patterns found",
    maxItems = 50
})
