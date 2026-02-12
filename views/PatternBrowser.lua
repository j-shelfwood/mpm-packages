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

local AEInterface = mpm('peripherals/AEInterface')
local GridDisplay = mpm('utils/GridDisplay')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

local module

module = {
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

    new = function(monitor, config)
        config = config or {}
        local width, height = monitor.getSize()

        local self = {
            monitor = monitor,
            width = width,
            height = height,
            sortBy = config.sortBy or "output",
            maxDisplay = config.maxDisplay or 50,
            interface = nil,
            display = GridDisplay.new(monitor),
            initialized = false
        }

        local ok, interface = pcall(AEInterface.new)
        if ok and interface then
            self.interface = interface
        end

        return self
    end,

    mount = function()
        return AEInterface.exists()
    end,

    -- Extract output name from pattern
    getOutputName = function(pattern)
        if pattern.primaryOutput and pattern.primaryOutput.name then
            return pattern.primaryOutput.name
        elseif pattern.outputs and #pattern.outputs > 0 and pattern.outputs[1].name then
            return pattern.outputs[1].name
        end
        return "unknown"
    end,

    -- Extract display name from pattern
    getDisplayName = function(pattern)
        if pattern.primaryOutput and pattern.primaryOutput.displayName then
            return pattern.primaryOutput.displayName
        elseif pattern.outputs and #pattern.outputs > 0 and pattern.outputs[1].displayName then
            return pattern.outputs[1].displayName
        end
        return "Unknown"
    end,

    -- Count total inputs in pattern
    countInputs = function(pattern)
        if not pattern.inputs then return 0 end
        return #pattern.inputs
    end,

    -- Get primary input display name
    getPrimaryInputName = function(pattern)
        if not pattern.inputs or #pattern.inputs == 0 then
            return "No inputs"
        end
        
        local firstInput = pattern.inputs[1]
        if firstInput and firstInput.primaryInput then
            if firstInput.primaryInput.displayName then
                return firstInput.primaryInput.displayName
            elseif firstInput.primaryInput.name then
                return Text.prettifyName(firstInput.primaryInput.name)
            end
        end
        
        return "Unknown input"
    end,

    -- Get pattern type color
    getPatternTypeColor = function(patternType)
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
    end,

    formatPattern = function(pattern)
        local displayName = module.getDisplayName(pattern)
        local inputCount = module.countInputs(pattern)
        local patternType = pattern.patternType or "unknown"
        local typeColor = module.getPatternTypeColor(patternType)

        local lines = {
            displayName,
            inputCount .. " input" .. (inputCount ~= 1 and "s" or ""),
            "[" .. (patternType:sub(1, 1):upper() .. patternType:sub(2)) .. "]"
        }

        local lineColors = {
            colors.white,
            colors.gray,
            typeColor
        }

        return {
            lines = lines,
            colors = lineColors
        }
    end,

    render = function(self)
        if not self.initialized then
            self.monitor.clear()
            self.initialized = true
        end

        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)

        if not self.interface then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No AE2 peripheral", colors.red)
            return
        end

        -- Get all patterns
        local ok, patterns = pcall(function() 
            return self.interface.bridge.getPatterns()
        end)
        
        if not ok or not patterns then
            MonitorHelpers.writeCentered(self.monitor, 1, "Error fetching patterns", colors.red)
            return
        end

        -- Yield after peripheral call
        Yield.yield()

        -- Handle no patterns
        if #patterns == 0 then
            self.monitor.clear()
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "No Patterns", colors.yellow)
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "No crafting patterns found", colors.gray)
            return
        end

        -- Sort patterns
        if self.sortBy == "output" then
            table.sort(patterns, function(a, b)
                local nameA = module.getDisplayName(a)
                local nameB = module.getDisplayName(b)
                return nameA < nameB
            end)
        elseif self.sortBy == "inputs" then
            table.sort(patterns, function(a, b)
                local countA = module.countInputs(a)
                local countB = module.countInputs(b)
                if countA == countB then
                    return module.getDisplayName(a) < module.getDisplayName(b)
                end
                return countA > countB
            end)
        end

        -- Limit display
        local maxItems = self.maxDisplay
        local displayPatterns = {}
        for i = 1, math.min(#patterns, maxItems) do
            displayPatterns[i] = patterns[i]
        end

        -- Draw header
        self.monitor.clear()
        self.monitor.setTextColor(colors.cyan)
        self.monitor.setCursorPos(1, 1)
        self.monitor.write("PATTERNS")
        self.monitor.setTextColor(colors.gray)
        local countStr = " (" .. #patterns .. " total)"
        self.monitor.write(Text.truncateMiddle(countStr, self.width - 9))

        -- Display patterns in grid
        self.display:display(displayPatterns, module.formatPattern)

        self.monitor.setTextColor(colors.white)
    end
}

return module
