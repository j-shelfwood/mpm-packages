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
local AEViewSupport = mpm('views/AEViewSupport')
local Text = mpm('utils/Text')
local Core = mpm('ui/Core')
local ModalOverlay = mpm('ui/ModalOverlay')

local listenEvents, onEvent = AEViewSupport.buildListener({ "patterns" })

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
    ModalOverlay.show(self, {
        maxWidth = 35,
        maxHeight = 12,
        title = getDisplayName(pattern),
        titleBackgroundColor = colors.lightGray,
        titleTextColor = colors.black,
        closeOnOutside = true,
        render = function(monitor, frame, state, addAction)
            local contentY = frame.y1 + 2
            local contentWidth = frame.width - 2

            local patternType = pattern.patternType or "unknown"
            monitor.setTextColor(getPatternTypeColor(patternType))
            monitor.setCursorPos(frame.x1 + 1, contentY)
            monitor.write("Type: " .. patternType)
            contentY = contentY + 1

            local outputCount = getOutputCount(pattern)
            if outputCount then
                monitor.setTextColor(colors.white)
                monitor.setCursorPos(frame.x1 + 1, contentY)
                monitor.write("Output: x" .. Text.formatNumber(outputCount, 0))
                contentY = contentY + 1
            end

            monitor.setTextColor(colors.cyan)
            monitor.setCursorPos(frame.x1 + 1, contentY)
            monitor.write("Inputs (" .. countInputs(pattern) .. "):")
            contentY = contentY + 1

            local maxInputs = frame.y2 - contentY - 1
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
                    monitor.setCursorPos(frame.x1 + 2, contentY)
                    monitor.write("- " .. Core.truncate(inputName, contentWidth - 8) .. " x" .. inputCount)
                    contentY = contentY + 1
                end

                if #pattern.inputs > maxInputs then
                    monitor.setTextColor(colors.gray)
                    monitor.setCursorPos(frame.x1 + 2, contentY)
                    monitor.write("+" .. (#pattern.inputs - maxInputs) .. " more...")
                end
            end

            local closeLabel = "[Close]"
            local closeX = frame.x1 + math.floor((frame.width - #closeLabel) / 2)
            local closeY = frame.y2 - 1
            monitor.setTextColor(colors.red)
            monitor.setCursorPos(closeX, closeY)
            monitor.write(closeLabel)
            addAction("close", closeX, closeY, closeX + #closeLabel - 1, closeY)
        end,
        onTouch = function(monitor, frame, state, tx, ty, action)
            if action == "close" then
                return true
            end
            return false
        end
    })
end

return BaseView.interactive({
    sleepTime = 10,
    listenEvents = listenEvents,
    onEvent = onEvent,

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
            return AEViewSupport.mount()
        end,

    init = function(self, config)
        AEViewSupport.init(self)
        self.sortBy = config.sortBy or "output"
        self.totalPatterns = 0
    end,

    getData = function(self)
        -- Lazy re-init: retry if host not yet discovered at init time
        if not AEViewSupport.ensureInterface(self) then return nil end

        local patterns = self.interface:getPatterns()
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
