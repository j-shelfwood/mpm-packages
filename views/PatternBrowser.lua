-- PatternBrowser.lua
-- Interactive browser for all crafting patterns in the ME network
-- Touch a pattern to see detailed inputs/outputs in overlay
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
local Core = mpm('ui/Core')

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

local function getOutputCount(pattern)
    if pattern.primaryOutput and pattern.primaryOutput.count then
        return pattern.primaryOutput.count
    elseif pattern.outputs and #pattern.outputs > 0 and pattern.outputs[1].count then
        return pattern.outputs[1].count
    end
    return nil
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

local function getPatternTypeShort(patternType)
    if patternType == "crafting" then return "C"
    elseif patternType == "processing" then return "P"
    elseif patternType == "smithing" then return "S"
    elseif patternType == "stonecutting" then return "X"
    else return "?"
    end
end

-- Pattern detail overlay (blocking)
local function showPatternDetail(self, pattern)
    local monitor = self.monitor
    local width, height = monitor.getSize()

    -- Calculate overlay bounds
    local overlayWidth = math.min(width - 2, 35)
    local overlayHeight = math.min(height - 2, 12)
    local x1 = math.floor((width - overlayWidth) / 2) + 1
    local y1 = math.floor((height - overlayHeight) / 2) + 1
    local x2 = x1 + overlayWidth - 1
    local y2 = y1 + overlayHeight - 1

    -- Use stored peripheral name (monitor is a window buffer, not a peripheral)
    local monitorName = self.peripheralName

    while true do
        -- Draw background
        monitor.setBackgroundColor(colors.gray)
        for y = y1, y2 do
            monitor.setCursorPos(x1, y)
            monitor.write(string.rep(" ", overlayWidth))
        end

        -- Title bar
        local displayName = getDisplayName(pattern)
        monitor.setBackgroundColor(colors.lightGray)
        monitor.setTextColor(colors.black)
        monitor.setCursorPos(x1, y1)
        monitor.write(string.rep(" ", overlayWidth))
        monitor.setCursorPos(x1 + 1, y1)
        monitor.write(Core.truncate(displayName, overlayWidth - 2))

        -- Content
        monitor.setBackgroundColor(colors.gray)
        local contentY = y1 + 2
        local contentWidth = overlayWidth - 2

        -- Pattern type
        local patternType = pattern.patternType or "unknown"
        monitor.setTextColor(getPatternTypeColor(patternType))
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.write("Type: " .. patternType)
        contentY = contentY + 1

        -- Output count
        local outputCount = getOutputCount(pattern)
        if outputCount then
            monitor.setTextColor(colors.white)
            monitor.setCursorPos(x1 + 1, contentY)
            monitor.write("Output: x" .. Text.formatNumber(outputCount, 0))
            contentY = contentY + 1
        end

        -- Inputs header
        monitor.setTextColor(colors.cyan)
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.write("Inputs (" .. countInputs(pattern) .. "):")
        contentY = contentY + 1

        -- List inputs (up to available space)
        local maxInputs = y2 - contentY - 1  -- Leave room for close button
        if pattern.inputs then
            for i = 1, math.min(#pattern.inputs, maxInputs) do
                local input = pattern.inputs[i]
                local inputName = "?"
                local inputCount = 1

                if input.primaryInput then
                    inputName = input.primaryInput.displayName or input.primaryInput.name or "?"
                    inputCount = input.primaryInput.count or 1
                end

                monitor.setTextColor(colors.lightGray)
                monitor.setCursorPos(x1 + 2, contentY)
                local inputText = "- " .. Core.truncate(inputName, contentWidth - 8) .. " x" .. inputCount
                monitor.write(inputText)
                contentY = contentY + 1
            end

            if #pattern.inputs > maxInputs then
                monitor.setTextColor(colors.gray)
                monitor.setCursorPos(x1 + 2, contentY)
                monitor.write("+" .. (#pattern.inputs - maxInputs) .. " more...")
            end
        end

        -- Close button
        monitor.setTextColor(colors.red)
        monitor.setCursorPos(x1 + math.floor((overlayWidth - 7) / 2), y2 - 1)
        monitor.write("[Close]")

        Core.resetColors(monitor)

        -- Wait for touch
        local event, side, tx, ty = os.pullEvent("monitor_touch")

        if side == monitorName then
            -- Close button or outside overlay
            if ty == y2 - 1 or tx < x1 or tx > x2 or ty < y1 or ty > y2 then
                return
            end
        end
    end
end

return BaseView.interactive({
    sleepTime = 10,

    configSchema = {
        {
            key = "sortBy",
            type = "select",
            label = "Sort By",
            options = {
                { value = "output", label = "Output Name" },
                { value = "inputs", label = "Input Count" },
                { value = "type", label = "Pattern Type" }
            },
            default = "output"
        }
    },

    mount = function()
        return AEInterface.exists()
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil
        self.sortBy = config.sortBy or "output"
        self.totalPatterns = 0
    end,

    getData = function(self)
        if not self.interface then return nil end

        local patterns = self.interface.bridge.getPatterns()
        if not patterns then return {} end

        self.totalPatterns = #patterns

        -- Sort patterns
        if self.sortBy == "output" then
            table.sort(patterns, function(a, b)
                return getDisplayName(a) < getDisplayName(b)
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
        elseif self.sortBy == "type" then
            table.sort(patterns, function(a, b)
                local typeA = a.patternType or "z"
                local typeB = b.patternType or "z"
                if typeA == typeB then
                    return getDisplayName(a) < getDisplayName(b)
                end
                return typeA < typeB
            end)
        end

        return patterns
    end,

    header = function(self, data)
        return {
            text = "PATTERNS",
            color = colors.cyan,
            secondary = " (" .. self.totalPatterns .. ")",
            secondaryColor = colors.gray
        }
    end,

    formatItem = function(self, pattern)
        local displayName = getDisplayName(pattern)
        local outputCount = getOutputCount(pattern)
        local patternType = pattern.patternType or "unknown"
        local typeColor = getPatternTypeColor(patternType)

        -- Compact display: name | count | type indicator
        local countStr = outputCount and ("x" .. Text.formatNumber(outputCount, 0)) or ""
        local typeChar = "[" .. getPatternTypeShort(patternType) .. "]"

        return {
            lines = { displayName, countStr .. " " .. typeChar },
            colors = { colors.white, typeColor },
            touchAction = "detail",
            touchData = pattern
        }
    end,

    onItemTouch = function(self, pattern, action)
        -- Show pattern detail overlay (blocking)
        showPatternDetail(self, pattern)
    end,

    footer = function(self, data)
        return {
            text = "Touch pattern for details",
            color = colors.gray
        }
    end,

    emptyMessage = "No crafting patterns found"
})
