-- ConfigMode.lua
-- Configuration overlay controller

local Overlay = mpm('ui/Overlay')
local Button = mpm('ui/Button')
local Toggle = mpm('ui/Toggle')
local Stepper = mpm('ui/Stepper')
local Select = mpm('ui/Select')
local ConfigSchema = mpm('shelfos/view/ConfigSchema')

local ConfigMode = {}

-- Show configuration overlay for a monitor
-- @param monitor Monitor manager instance
-- @param schema Config schema
-- @param currentConfig Current configuration
-- @return updated config or nil if cancelled
function ConfigMode.show(monitor, schema, currentConfig)
    if not monitor or not monitor.peripheral then
        return nil
    end

    local peripheral = monitor.peripheral
    local monitorName = monitor.peripheralName
    local width, height = peripheral.getSize()

    -- Check if we have any config options
    if not schema or #schema == 0 then
        ConfigMode.showMessage(peripheral, "No configuration options")
        sleep(1.5)
        return nil
    end

    -- Create overlay
    local overlay = Overlay.new(peripheral)
    overlay:setTitle("Configuration")
    overlay:setColors(colors.gray, colors.blue, colors.white, colors.white)

    -- Build widgets for each schema field
    local widgets = {}
    local startY = 3
    local config = {}

    -- Copy current config
    for k, v in pairs(currentConfig or {}) do
        config[k] = v
    end

    for i, field in ipairs(schema) do
        local y = startY + (i - 1) * 2
        local widget = nil
        local currentValue = config[field.key]
        if currentValue == nil then
            currentValue = field.default
        end

        if field.type == ConfigSchema.FieldType.BOOLEAN then
            widget = Toggle.new(peripheral, 2, y, field.label, currentValue, function(newValue)
                config[field.key] = newValue
            end)

        elseif field.type == ConfigSchema.FieldType.NUMBER then
            widget = Stepper.new(peripheral, 2, y, field.label, currentValue, {
                min = field.min,
                max = field.max,
                step = field.step or 1,
                largeStep = field.largeStep or 10
            }, function(newValue)
                config[field.key] = newValue
            end)

        elseif field.type == ConfigSchema.FieldType.SELECT then
            local options = field.options
            -- Resolve dynamic options
            if type(options) == "function" then
                options = options()
            end

            local selectedIndex = 1
            for j, opt in ipairs(options) do
                local val = type(opt) == "table" and (opt.value or opt[1]) or opt
                if val == currentValue then
                    selectedIndex = j
                    break
                end
            end

            widget = Select.new(peripheral, 2, y, field.label, options, selectedIndex, function(newValue)
                config[field.key] = newValue
            end)

        elseif field.type == ConfigSchema.FieldType.PERIPHERAL then
            local options = ConfigSchema.getPeripheralOptions(field.peripheralType)
            local selectedIndex = 1
            for j, opt in ipairs(options) do
                if opt.value == currentValue then
                    selectedIndex = j
                    break
                end
            end

            widget = Select.new(peripheral, 2, y, field.label, options, selectedIndex, function(newValue)
                config[field.key] = newValue
            end)

        elseif field.type == ConfigSchema.FieldType.STRING then
            -- String fields require text input - show current value and indicator
            -- Full implementation would request input via pocket computer
            widget = {
                x = 2,
                y = y,
                render = function(self)
                    peripheral.setBackgroundColor(colors.black)
                    peripheral.setTextColor(colors.white)
                    peripheral.setCursorPos(self.x, self.y)
                    peripheral.write(field.label .. ": ")
                    peripheral.setTextColor(colors.yellow)
                    local val = tostring(config[field.key] or field.default or "")
                    if #val > 10 then
                        val = val:sub(1, 7) .. "..."
                    end
                    peripheral.write("[" .. val .. "]")
                    peripheral.setTextColor(colors.gray)
                    peripheral.write(" (tap)")
                end,
                handleTouch = function(self, x, y)
                    if y == self.y then
                        -- Would trigger text input request
                        -- For now, just flash
                        peripheral.setBackgroundColor(colors.yellow)
                        peripheral.setCursorPos(self.x, self.y)
                        peripheral.write(string.rep(" ", width - 2))
                        sleep(0.2)
                        self:render()
                        return true
                    end
                    return false
                end
            }
        end

        if widget then
            table.insert(widgets, widget)
        end
    end

    -- Add Save/Cancel buttons
    local buttonY = height - 1
    local saveButton = Button.new(peripheral, 2, buttonY, "Save", nil)
    saveButton:setColors(colors.green, colors.white)

    local cancelButton = Button.new(peripheral, width - 8, buttonY, "Cancel", nil)
    cancelButton:setColors(colors.red, colors.white)

    -- Render initial state
    peripheral.setBackgroundColor(colors.gray)
    peripheral.clear()

    -- Title bar
    peripheral.setBackgroundColor(colors.blue)
    peripheral.setCursorPos(1, 1)
    peripheral.write(string.rep(" ", width))
    peripheral.setTextColor(colors.white)
    local title = "Configuration"
    peripheral.setCursorPos(math.floor((width - #title) / 2) + 1, 1)
    peripheral.write(title)

    peripheral.setBackgroundColor(colors.gray)

    -- Render widgets
    for _, widget in ipairs(widgets) do
        widget:render()
    end

    saveButton:render()
    cancelButton:render()

    -- Event loop
    local running = true
    local saved = false

    while running do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "monitor_touch" and p1 == monitorName then
            -- Check buttons
            if saveButton:contains(p2, p3) then
                saved = true
                running = false
            elseif cancelButton:contains(p2, p3) then
                running = false
            else
                -- Check widgets
                for _, widget in ipairs(widgets) do
                    if widget.handleTouch and widget:handleTouch(p2, p3) then
                        break
                    end
                end
            end
        elseif event == "key" and p1 == keys.q then
            running = false
        end
    end

    -- Clear overlay
    peripheral.setBackgroundColor(colors.black)
    peripheral.clear()

    if saved then
        return config
    else
        return nil
    end
end

-- Show a simple message
function ConfigMode.showMessage(peripheral, message)
    local width, height = peripheral.getSize()

    peripheral.setBackgroundColor(colors.gray)
    peripheral.clear()

    peripheral.setTextColor(colors.white)
    local x = math.floor((width - #message) / 2) + 1
    local y = math.floor(height / 2)
    peripheral.setCursorPos(x, y)
    peripheral.write(message)
end

return ConfigMode
