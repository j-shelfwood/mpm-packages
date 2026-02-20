-- ConfigUI.lua
-- Renders configuration menus on monitors for view setup
-- Handles different config field types: number, boolean, item:id, fluid:id, select, peripheral, multiselect
-- Uses ui/ widgets for consistent styling
--
-- Split module:
--   ConfigUIInputs.lua - Number stepper and boolean toggle dialogs

local AEInterface = mpm('peripherals/AEInterface')
local Peripherals = mpm('utils/Peripherals')
local Text = mpm('utils/Text')
local Core = mpm('ui/Core')
local ScrollableList = mpm('ui/ScrollableList')
local EventLoop = mpm('ui/EventLoop')
local Inputs = mpm('shelfos/core/ConfigUIInputs')
-- Note: Uses os.pullEvent directly - each monitor runs in its own coroutine with parallel API

local ConfigUI = {}

-- Fetch items from AE2 for item:id picker
local function getAE2Items()
    local ok, exists = pcall(AEInterface.exists)
    if not ok or not exists then return {} end

    local okNew, interface = pcall(AEInterface.new)
    if not okNew or not interface then return {} end

    local itemsOk, items = pcall(function() return interface:items() end)
    if not itemsOk or not items then return {} end

    -- Sort by count descending
    table.sort(items, function(a, b)
        return (a.count or 0) > (b.count or 0)
    end)

    return items
end

-- Fetch fluids from AE2 for fluid:id picker
local function getAE2Fluids()
    local ok, exists = pcall(AEInterface.exists)
    if not ok or not exists then return {} end

    local okNew, interface = pcall(AEInterface.new)
    if not okNew or not interface then return {} end

    local fluidsOk, fluids = pcall(function() return interface:fluids() end)
    if not fluidsOk or not fluids then return {} end

    -- Sort by amount descending
    table.sort(fluids, function(a, b)
        return (a.amount or 0) > (b.amount or 0)
    end)

    return fluids
end

-- Get peripherals filtered by type (uses Peripherals module for network transparency)
local function getPeripherals(filterType)
    local names = Peripherals.getNames()
    local result = {}

    for _, name in ipairs(names) do
        if not filterType or Peripherals.hasType(name, filterType) then
            table.insert(result, {
                name = name,
                label = Peripherals.getDisplayName(name) or name,
                type = Peripherals.getType(name)
            })
        end
    end

    return result
end

-- Draw a picker list using ui/List widget
-- Returns selected value or nil if cancelled
function ConfigUI.drawPicker(monitor, title, options, currentValue, formatFn)
    local function getValue(opt)
        if type(opt) == "table" then
            return opt.value or opt.name or opt
        end
        return opt
    end

    local selectedItem = ScrollableList.new(monitor, options, {
        title = title,
        selected = currentValue,
        formatFn = formatFn,
        valueFn = getValue,
        cancelText = "Cancel",
        showPageIndicator = false
    }):show()

    if selectedItem == nil then
        return nil
    end
    return getValue(selectedItem)
end

local function cloneArray(values)
    local copy = {}
    for i, value in ipairs(values or {}) do
        copy[i] = value
    end
    return copy
end

local function normalizeOptions(options)
    local normalized = {}
    for _, option in ipairs(options or {}) do
        if type(option) == "table" then
            table.insert(normalized, {
                value = option.value or option.name or tostring(option.label or ""),
                label = option.label or option.name or tostring(option.value)
            })
        else
            table.insert(normalized, {
                value = tostring(option),
                label = tostring(option)
            })
        end
    end
    return normalized
end

local function resolveFieldOptions(field, config)
    local options = field.options
    if type(options) == "function" then
        options = options(config)
    end
    return normalizeOptions(options or {})
end

-- Multi-select picker for monitor configuration.
-- Returns selected array (in option order) or nil if cancelled.
function ConfigUI.drawMultiPicker(monitor, title, options, currentValues)
    local width, height = monitor.getSize()
    local monitorName = Peripherals.getName(monitor)
    local normalized = normalizeOptions(options)
    local selected = {}

    for _, value in ipairs(currentValues or {}) do
        selected[tostring(value)] = true
    end

    local listStartY = 3
    local listEndY = math.max(listStartY, height - 3)
    local rowsPerPage = math.max(1, listEndY - listStartY + 1)
    local page = 1

    while true do
        Core.clear(monitor)
        Core.drawBar(monitor, 1, title, Core.COLORS.titleBar, Core.COLORS.titleText)

        local pageCount = math.max(1, math.ceil(#normalized / rowsPerPage))
        if page > pageCount then page = pageCount end

        monitor.setTextColor(Core.COLORS.textMuted)
        monitor.setBackgroundColor(colors.black)
        monitor.setCursorPos(2, 2)
        monitor.write("Tap to toggle")
        local pageText = string.format("%d/%d", page, pageCount)
        local pageX = math.max(2, width - #pageText - 1)
        monitor.setCursorPos(pageX, 2)
        monitor.write(pageText)
        if page > 1 then
            monitor.setCursorPos(1, 2)
            monitor.write("<")
        end
        if page < pageCount then
            monitor.setCursorPos(width, 2)
            monitor.write(">")
        end

        local startIdx = (page - 1) * rowsPerPage + 1
        local endIdx = math.min(#normalized, startIdx + rowsPerPage - 1)
        local touchRows = {}

        for idx = startIdx, endIdx do
            local y = listStartY + (idx - startIdx)
            local opt = normalized[idx]
            local isSelected = selected[tostring(opt.value)] == true
            local marker = isSelected and "[x] " or "[ ] "
            local display = Core.truncateMiddle(marker .. opt.label, width - 2)
            monitor.setCursorPos(2, y)
            monitor.setTextColor(isSelected and colors.lime or Core.COLORS.text)
            monitor.write(display)
            touchRows[y] = tostring(opt.value)
        end

        Core.drawBar(monitor, height - 2, "Clear", Core.COLORS.neutralButton, Core.COLORS.text)
        Core.drawBar(monitor, height - 1, "Save", Core.COLORS.confirmButton, Core.COLORS.text)
        Core.drawBar(monitor, height, "Cancel", Core.COLORS.cancelButton, Core.COLORS.text)
        Core.resetColors(monitor)

        local _, x, y = EventLoop.waitForMonitorTouch(monitorName)

        if y == height - 1 then
            local result = {}
            for _, opt in ipairs(normalized) do
                if selected[tostring(opt.value)] then
                    table.insert(result, opt.value)
                end
            end
            return result
        end

        if y == height then
            return nil
        end

        if y == height - 2 then
            selected = {}
        elseif y == 2 then
            if x <= math.min(3, width) and page > 1 then
                page = page - 1
            elseif x >= math.max(1, width - 2) and page < pageCount then
                page = page + 1
            end
        elseif touchRows[y] then
            local value = touchRows[y]
            selected[value] = not selected[value]
        end
    end
end

-- Delegate to ConfigUIInputs for number input
function ConfigUI.drawNumberInput(monitor, title, currentValue, min, max, presets, step, largeStep)
    return Inputs.drawNumberInput(monitor, title, currentValue, min, max, presets, step, largeStep)
end

-- Delegate to ConfigUIInputs for boolean input
function ConfigUI.drawBooleanInput(monitor, title, currentValue)
    return Inputs.drawBooleanInput(monitor, title, currentValue)
end

-- Draw the main config menu for a view
-- schema: array of {key, type, label, default, ...}
-- currentConfig: current config values
-- Returns: new config table or nil if cancelled
function ConfigUI.drawConfigMenu(monitor, viewName, schema, currentConfig)
    local width, height = monitor.getSize()
    currentConfig = currentConfig or {}

    -- Build working config with defaults
    local config = {}
    for _, field in ipairs(schema) do
        if currentConfig[field.key] ~= nil then
            config[field.key] = currentConfig[field.key]
        elseif field.default ~= nil then
            if type(field.default) == "table" then
                config[field.key] = cloneArray(field.default)
            else
                config[field.key] = field.default
            end
        end
    end

    local monitorName = Peripherals.getName(monitor)

    while true do
        Core.clear(monitor)

        -- Title bar
        Core.drawBar(monitor, 1, "Configure", Core.COLORS.titleBar, Core.COLORS.titleText)

        -- View name
        monitor.setTextColor(Core.COLORS.textMuted)
        local nameDisplay = Core.truncateMiddle(viewName, width - 4)
        monitor.setCursorPos(2, 2)
        monitor.write(nameDisplay)

        -- Config fields
        local fieldBounds = {}
        local startY = 4

        for i, field in ipairs(schema) do
            local y = startY + (i - 1) * 2
            if y > height - 3 then break end

            -- Label
            monitor.setTextColor(Core.COLORS.text)
            monitor.setCursorPos(2, y)
            monitor.write(field.label or field.key)

            -- Value display
            local valueDisplay = "Not set"
            local valueColor = Core.COLORS.textMuted

            if config[field.key] ~= nil then
                valueColor = colors.lime

                if field.type == "item:id" or field.type == "fluid:id" then
                    valueDisplay = Text.prettifyName(config[field.key])
                elseif field.type == "number" then
                    valueDisplay = Text.formatNumber(config[field.key], 0)
                elseif field.type == "boolean" then
                    valueDisplay = config[field.key] and "Yes" or "No"
                elseif field.type == "peripheral" then
                    valueDisplay = config[field.key]
                elseif field.type == "multiselect" then
                    local selectedValues = config[field.key]
                    if type(selectedValues) == "table" and #selectedValues > 0 then
                        local options = resolveFieldOptions(field, config)
                        local labelsByValue = {}
                        for _, opt in ipairs(options) do
                            labelsByValue[tostring(opt.value)] = opt.label
                        end
                        if #selectedValues == 1 then
                            local only = tostring(selectedValues[1])
                            valueDisplay = labelsByValue[only] or only
                        else
                            valueDisplay = tostring(#selectedValues) .. " selected"
                        end
                    else
                        valueDisplay = "None selected"
                        valueColor = Core.COLORS.textMuted
                    end
                else
                    valueDisplay = tostring(config[field.key])
                end
            end

            -- Truncate if needed
            local maxValueLen = width - 6
            valueDisplay = Core.truncateMiddle(valueDisplay, maxValueLen)

            monitor.setTextColor(valueColor)
            monitor.setCursorPos(2, y + 1)
            monitor.write("  " .. valueDisplay .. " ")
            monitor.setTextColor(Core.COLORS.textMuted)
            monitor.write("[>]")

            table.insert(fieldBounds, {
                y1 = y, y2 = y + 1,
                field = field
            })
        end

        -- Save/Cancel buttons
        local saveY = height - 1
        local cancelY = height

        Core.drawBar(monitor, saveY, "Save", Core.COLORS.confirmButton, Core.COLORS.text)
        Core.drawBar(monitor, cancelY, "Cancel", Core.COLORS.cancelButton, Core.COLORS.text)

        Core.resetColors(monitor)

        -- Wait for touch on THIS monitor only
        local _, x, y = EventLoop.waitForMonitorTouch(monitorName)

        -- Save
        if y == saveY then
            return config
        end

        -- Cancel
        if y == cancelY then
            return nil
        end

        -- Field selection
        for _, bounds in ipairs(fieldBounds) do
            if y >= bounds.y1 and y <= bounds.y2 then
                local field = bounds.field
                local newValue = nil

                if field.type == "item:id" then
                    local items = getAE2Items()
                    local options = {}
                    for _, item in ipairs(items) do
                        table.insert(options, {
                            value = item.registryName,
                            label = Text.prettifyName(item.registryName) .. " (" .. Text.formatNumber(item.count or 0, 0) .. ")"
                        })
                    end
                    newValue = ConfigUI.drawPicker(monitor, "Select Item", options, config[field.key], function(opt)
                        return opt.label
                    end)

                elseif field.type == "fluid:id" then
                    local fluids = getAE2Fluids()
                    local options = {}
                    for _, fluid in ipairs(fluids) do
                        local buckets = math.floor((fluid.amount or 0) / 1000)
                        table.insert(options, {
                            value = fluid.registryName,
                            label = Text.prettifyName(fluid.registryName) .. " (" .. Text.formatNumber(buckets, 0) .. "B)"
                        })
                    end
                    newValue = ConfigUI.drawPicker(monitor, "Select Fluid", options, config[field.key], function(opt)
                        return opt.label
                    end)

                elseif field.type == "number" then
                    newValue = ConfigUI.drawNumberInput(
                        monitor,
                        field.label or field.key,
                        config[field.key],
                        field.min,
                        field.max,
                        field.presets,
                        field.step,
                        field.largeStep
                    )

                elseif field.type == "boolean" then
                    newValue = ConfigUI.drawBooleanInput(
                        monitor,
                        field.label or field.key,
                        config[field.key]
                    )

                elseif field.type == "peripheral" then
                    local peripherals = getPeripherals(field.filter)
                    local options = {}
                    for _, p in ipairs(peripherals) do
                        table.insert(options, {
                            value = p.name,
                            label = (p.label or p.name) .. " (" .. p.type .. ")"
                        })
                    end
                    newValue = ConfigUI.drawPicker(monitor, "Select Peripheral", options, config[field.key], function(opt)
                        return opt.label
                    end)

                elseif field.type == "select" then
                    local options = resolveFieldOptions(field, config)
                    -- Handle empty options with informative message
                    if not options or #options == 0 then
                        local Dialog = mpm('ui/Dialog')
                        Dialog.confirm(
                            monitor,
                            field.label or field.key,
                            "No options available. Check peripheral connections."
                        )
                    else
                        newValue = ConfigUI.drawPicker(monitor, field.label or field.key, options, config[field.key])
                    end
                elseif field.type == "multiselect" then
                    local options = resolveFieldOptions(field, config)
                    if not options or #options == 0 then
                        local Dialog = mpm('ui/Dialog')
                        Dialog.confirm(
                            monitor,
                            field.label or field.key,
                            "No options available. Check peripheral connections."
                        )
                    else
                        local existing = config[field.key]
                        if type(existing) ~= "table" then
                            existing = {}
                        end
                        newValue = ConfigUI.drawMultiPicker(
                            monitor,
                            field.label or field.key,
                            options,
                            cloneArray(existing)
                        )
                    end
                end

                if newValue ~= nil then
                    config[field.key] = newValue
                end

                break
            end
        end
    end
end

return ConfigUI
