-- ConfigUI.lua
-- Renders configuration menus on monitors for view setup
-- Handles different config field types: number, boolean, item:id, fluid:id, select, peripheral
-- Uses ui/ widgets for consistent styling

local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local Core = mpm('ui/Core')
local List = mpm('ui/List')
local Stepper = mpm('ui/Stepper')
local Toggle = mpm('ui/Toggle')
local TimerDispatch = mpm('utils/TimerDispatch')

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

-- Get peripherals filtered by type
local function getPeripherals(filterType)
    local names = peripheral.getNames()
    local result = {}

    for _, name in ipairs(names) do
        if not filterType or peripheral.hasType(name, filterType) then
            table.insert(result, {
                name = name,
                type = peripheral.getType(name)
            })
        end
    end

    return result
end

-- Draw a picker list using ui/List widget
-- Returns selected value or nil if cancelled
function ConfigUI.drawPicker(monitor, title, options, currentValue, formatFn)
    return List.new(monitor, options, {
        title = title,
        selected = currentValue,
        formatFn = formatFn,
        cancelText = "Cancel"
    }):show()
end

-- Draw number input using ui/Stepper widget
-- @param monitor Monitor peripheral
-- @param title Dialog title
-- @param currentValue Current value
-- @param min Minimum value
-- @param max Maximum value
-- @param presets Array of preset values
-- @param step Small step increment (default: 1)
-- @param largeStep Large step increment (default: 100)
-- @return Selected value or nil if cancelled
function ConfigUI.drawNumberInput(monitor, title, currentValue, min, max, presets, step, largeStep)
    local width, height = monitor.getSize()
    min = min or 0
    max = max or 999999999
    presets = presets or {100, 500, 1000, 5000, 10000, 50000}
    step = step or 1
    largeStep = largeStep or 100

    local value = currentValue or presets[1] or 1000

    -- Create stepper widget
    local stepperY = 4
    local stepper = Stepper.new(monitor, 2, stepperY, "Value", value, {
        min = min,
        max = max,
        step = step,
        largeStep = largeStep,
        valueWidth = 10
    }, function(newValue)
        value = newValue
    end)

    while true do
        Core.clear(monitor)

        -- Title bar
        Core.drawBar(monitor, 1, title, Core.COLORS.titleBar, Core.COLORS.titleText)

        -- Current value display (formatted nicely)
        monitor.setTextColor(Core.COLORS.text)
        local valueStr = Text.formatNumber(value, 0)
        local valueX = Core.centerX(width, #valueStr)
        monitor.setCursorPos(valueX, 3)
        monitor.write(valueStr)

        -- Render stepper
        stepper:render()

        -- Preset buttons section
        monitor.setTextColor(Core.COLORS.textMuted)
        monitor.setCursorPos(2, stepperY + 2)
        monitor.write("Presets:")

        local btnY = stepperY + 3
        local btnX = 2
        local presetBounds = {}

        for i, preset in ipairs(presets) do
            local label = Text.formatNumber(preset, 0)
            if btnX + #label + 2 > width - 1 then
                btnY = btnY + 1
                btnX = 2
            end

            if preset == value then
                monitor.setBackgroundColor(Core.COLORS.confirmButton)
            else
                monitor.setBackgroundColor(Core.COLORS.neutralButton)
            end
            monitor.setTextColor(Core.COLORS.text)
            monitor.setCursorPos(btnX, btnY)
            monitor.write(" " .. label .. " ")

            table.insert(presetBounds, {
                x1 = btnX, x2 = btnX + #label + 1,
                y = btnY, value = preset
            })

            btnX = btnX + #label + 3
        end

        -- Save/Cancel buttons
        local saveY = height - 1
        local cancelY = height

        Core.drawBar(monitor, saveY, "Save", Core.COLORS.confirmButton, Core.COLORS.text)
        Core.drawBar(monitor, cancelY, "Cancel", Core.COLORS.cancelButton, Core.COLORS.text)

        Core.resetColors(monitor)

        -- Wait for touch
        local event, side, x, y = TimerDispatch.pullEvent("monitor_touch")

        -- Save
        if y == saveY then
            return value
        end

        -- Cancel
        if y == cancelY then
            return nil
        end

        -- Check stepper touch
        if stepper:handleTouch(x, y) then
            value = stepper:getValue()
        end

        -- Preset selection
        for _, btn in ipairs(presetBounds) do
            if y == btn.y and x >= btn.x1 and x <= btn.x2 then
                value = btn.value
                stepper:setValue(value)
                break
            end
        end
    end
end

-- Draw boolean toggle using ui/Toggle widget
-- @param monitor Monitor peripheral
-- @param title Dialog title
-- @param currentValue Current boolean value
-- @return Selected value or nil if cancelled
function ConfigUI.drawBooleanInput(monitor, title, currentValue)
    local width, height = monitor.getSize()
    local value = currentValue or false

    -- Create toggle widget
    local toggleY = math.floor(height / 2)
    local toggle = Toggle.new(monitor, 2, toggleY, "Enabled", value, function(newValue)
        value = newValue
    end)

    while true do
        Core.clear(monitor)

        -- Title bar
        Core.drawBar(monitor, 1, title, Core.COLORS.titleBar, Core.COLORS.titleText)

        -- Instructions
        monitor.setTextColor(Core.COLORS.textMuted)
        monitor.setCursorPos(2, 3)
        monitor.write("Toggle the setting:")

        -- Render toggle
        toggle:render()

        -- Save/Cancel buttons
        local saveY = height - 1
        local cancelY = height

        Core.drawBar(monitor, saveY, "Save", Core.COLORS.confirmButton, Core.COLORS.text)
        Core.drawBar(monitor, cancelY, "Cancel", Core.COLORS.cancelButton, Core.COLORS.text)

        Core.resetColors(monitor)

        -- Wait for touch
        local event, side, x, y = TimerDispatch.pullEvent("monitor_touch")

        -- Save
        if y == saveY then
            return value
        end

        -- Cancel
        if y == cancelY then
            return nil
        end

        -- Check toggle touch
        if toggle:handleTouch(x, y) then
            value = toggle:getValue()
        end
    end
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
            config[field.key] = field.default
        end
    end

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

        -- Wait for touch
        local event, side, x, y = TimerDispatch.pullEvent("monitor_touch")

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
                            label = p.name .. " (" .. p.type .. ")"
                        })
                    end
                    newValue = ConfigUI.drawPicker(monitor, "Select Peripheral", options, config[field.key], function(opt)
                        return opt.label
                    end)

                elseif field.type == "select" then
                    local options = field.options
                    if type(options) == "function" then
                        options = options()
                    end
                    -- Handle empty options with informative message
                    if not options or #options == 0 then
                        local Dialog = mpm('ui/Dialog')
                        Dialog.new(monitor, {
                            title = field.label or field.key,
                            message = "No options available.\nCheck peripheral connections.",
                            buttons = {{ label = "OK", value = true }}
                        }):show()
                    else
                        newValue = ConfigUI.drawPicker(monitor, field.label or field.key, options, config[field.key])
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
