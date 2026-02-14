-- ConfigUIInputs.lua
-- Input widgets for ConfigUI
-- Number stepper and boolean toggle dialogs
-- Extracted from ConfigUI.lua for maintainability

local Text = mpm('utils/Text')
local Core = mpm('ui/Core')
local Stepper = mpm('ui/Stepper')
local Toggle = mpm('ui/Toggle')

local ConfigUIInputs = {}

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
function ConfigUIInputs.drawNumberInput(monitor, title, currentValue, min, max, presets, step, largeStep)
    local width, height = monitor.getSize()
    local monitorName = peripheral.getName(monitor)
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

        -- Wait for touch on THIS monitor only
        local event, side, x, y
        repeat
            event, side, x, y = os.pullEvent("monitor_touch")
        until side == monitorName

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
function ConfigUIInputs.drawBooleanInput(monitor, title, currentValue)
    local width, height = monitor.getSize()
    local monitorName = peripheral.getName(monitor)
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

        -- Wait for touch on THIS monitor only
        local event, side, x, y
        repeat
            event, side, x, y = os.pullEvent("monitor_touch")
        until side == monitorName

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

return ConfigUIInputs
