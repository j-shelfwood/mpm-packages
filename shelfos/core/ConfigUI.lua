-- ConfigUI.lua
-- Renders configuration menus on monitors for view setup
-- Handles different config field types: number, item:id, fluid:id, select

local AEInterface = mpm('peripherals/AEInterface')

local ConfigUI = {}

-- Fetch items from AE2 for item:id picker
local function getAE2Items()
    local ok, exists = pcall(AEInterface.exists)
    if not ok or not exists then return {} end

    local interface = AEInterface.new()
    local itemsOk, items = pcall(AEInterface.items, interface)
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

    local interface = AEInterface.new()
    local fluidsOk, fluids = pcall(AEInterface.fluids, interface)
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

-- Prettify an item/fluid name for display
local function prettifyName(id)
    if not id then return "None" end
    local _, _, name = string.find(id, ":(.+)")
    if name then
        name = name:gsub("_", " ")
        return name:gsub("^%l", string.upper)
    end
    return id
end

-- Draw a picker list (items, fluids, or options)
-- Returns selected value or nil if cancelled
function ConfigUI.drawPicker(monitor, title, options, currentValue, formatFn)
    local width, height = monitor.getSize()
    formatFn = formatFn or function(opt) return opt.label or opt.name or tostring(opt) end

    local scrollOffset = 0
    local maxVisible = height - 4  -- Title, spacing, cancel bar

    -- Find current selection index
    local selectedIndex = 1
    for i, opt in ipairs(options) do
        local value = opt.value or opt.name or opt
        if value == currentValue then
            selectedIndex = i
            -- Scroll to show selection
            if selectedIndex > maxVisible then
                scrollOffset = selectedIndex - maxVisible
            end
            break
        end
    end

    while true do
        monitor.setBackgroundColor(colors.black)
        monitor.clear()

        -- Title bar
        monitor.setBackgroundColor(colors.blue)
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(1, 1)
        monitor.write(string.rep(" ", width))
        local titleX = math.floor((width - #title) / 2) + 1
        monitor.setCursorPos(titleX, 1)
        monitor.write(title)

        -- Options list
        monitor.setBackgroundColor(colors.black)
        local startY = 3

        for i = 1, math.min(maxVisible, #options - scrollOffset) do
            local optIndex = i + scrollOffset
            local opt = options[optIndex]
            if opt then
                local y = startY + i - 1
                local label = formatFn(opt)
                local value = opt.value or opt.name or opt

                -- Truncate if too long
                if #label > width - 4 then
                    label = label:sub(1, width - 7) .. "..."
                end

                if value == currentValue then
                    monitor.setBackgroundColor(colors.gray)
                    monitor.setTextColor(colors.white)
                    monitor.setCursorPos(1, y)
                    monitor.write(string.rep(" ", width))
                    monitor.setCursorPos(2, y)
                    monitor.write("> " .. label)
                else
                    monitor.setBackgroundColor(colors.black)
                    monitor.setTextColor(colors.lightGray)
                    monitor.setCursorPos(2, y)
                    monitor.write("  " .. label)
                end
            end
        end

        -- Scroll indicators
        if scrollOffset > 0 then
            monitor.setBackgroundColor(colors.black)
            monitor.setTextColor(colors.gray)
            monitor.setCursorPos(width, 3)
            monitor.write("^")
        end
        if scrollOffset + maxVisible < #options then
            monitor.setBackgroundColor(colors.black)
            monitor.setTextColor(colors.gray)
            monitor.setCursorPos(width, startY + maxVisible - 1)
            monitor.write("v")
        end

        -- Cancel bar
        local cancelY = height
        monitor.setBackgroundColor(colors.red)
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(1, cancelY)
        monitor.write(string.rep(" ", width))
        local cancelText = "Cancel"
        monitor.setCursorPos(math.floor((width - #cancelText) / 2) + 1, cancelY)
        monitor.write(cancelText)

        -- Wait for touch
        local event, side, x, y = os.pullEvent("monitor_touch")

        -- Cancel
        if y == cancelY then
            return nil
        end

        -- Scroll up
        if y == 3 and scrollOffset > 0 then
            scrollOffset = scrollOffset - 1
        -- Scroll down
        elseif y == startY + maxVisible - 1 and scrollOffset + maxVisible < #options then
            scrollOffset = scrollOffset + 1
        -- Option selection
        elseif y >= startY and y < startY + maxVisible then
            local optIndex = (y - startY + 1) + scrollOffset
            if optIndex >= 1 and optIndex <= #options then
                local opt = options[optIndex]
                return opt.value or opt.name or opt
            end
        end
    end
end

-- Draw number input (simple: tap +/- or preset values)
function ConfigUI.drawNumberInput(monitor, title, currentValue, min, max, presets)
    local width, height = monitor.getSize()
    min = min or 0
    max = max or 999999999
    presets = presets or {100, 500, 1000, 5000, 10000, 50000}

    local value = currentValue or presets[1] or 1000

    while true do
        monitor.setBackgroundColor(colors.black)
        monitor.clear()

        -- Title bar
        monitor.setBackgroundColor(colors.blue)
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(1, 1)
        monitor.write(string.rep(" ", width))
        local titleX = math.floor((width - #title) / 2) + 1
        monitor.setCursorPos(titleX, 1)
        monitor.write(title)

        -- Current value display
        monitor.setBackgroundColor(colors.black)
        monitor.setTextColor(colors.white)
        local valueStr = tostring(value)
        monitor.setCursorPos(math.floor((width - #valueStr) / 2) + 1, 3)
        monitor.write(valueStr)

        -- Preset buttons
        monitor.setTextColor(colors.lightGray)
        monitor.setCursorPos(2, 5)
        monitor.write("Presets:")

        local btnY = 6
        local btnX = 2
        local presetBounds = {}

        for i, preset in ipairs(presets) do
            local label = tostring(preset)
            if btnX + #label + 2 > width - 1 then
                btnY = btnY + 1
                btnX = 2
            end

            if preset == value then
                monitor.setBackgroundColor(colors.green)
            else
                monitor.setBackgroundColor(colors.gray)
            end
            monitor.setTextColor(colors.white)
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

        monitor.setBackgroundColor(colors.green)
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(1, saveY)
        monitor.write(string.rep(" ", width))
        monitor.setCursorPos(math.floor((width - 4) / 2) + 1, saveY)
        monitor.write("Save")

        monitor.setBackgroundColor(colors.red)
        monitor.setCursorPos(1, cancelY)
        monitor.write(string.rep(" ", width))
        monitor.setCursorPos(math.floor((width - 6) / 2) + 1, cancelY)
        monitor.write("Cancel")

        -- Wait for touch
        local event, side, x, y = os.pullEvent("monitor_touch")

        -- Save
        if y == saveY then
            return value
        end

        -- Cancel
        if y == cancelY then
            return nil
        end

        -- Preset selection
        for _, btn in ipairs(presetBounds) do
            if y == btn.y and x >= btn.x1 and x <= btn.x2 then
                value = btn.value
                break
            end
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
        monitor.setBackgroundColor(colors.black)
        monitor.clear()

        -- Title bar
        monitor.setBackgroundColor(colors.blue)
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(1, 1)
        monitor.write(string.rep(" ", width))
        local title = "Configure"
        monitor.setCursorPos(math.floor((width - #title) / 2) + 1, 1)
        monitor.write(title)

        -- View name
        monitor.setBackgroundColor(colors.black)
        monitor.setTextColor(colors.lightGray)
        monitor.setCursorPos(2, 2)
        local nameDisplay = viewName
        if #nameDisplay > width - 4 then
            nameDisplay = nameDisplay:sub(1, width - 7) .. "..."
        end
        monitor.write(nameDisplay)

        -- Config fields
        local fieldBounds = {}
        local startY = 4

        for i, field in ipairs(schema) do
            local y = startY + (i - 1) * 2
            if y > height - 3 then break end

            -- Label
            monitor.setTextColor(colors.white)
            monitor.setCursorPos(2, y)
            monitor.write(field.label or field.key)

            -- Value display
            local valueDisplay = "Not set"
            local valueColor = colors.gray

            if config[field.key] ~= nil then
                valueColor = colors.lime
                if field.type == "item:id" or field.type == "fluid:id" then
                    valueDisplay = prettifyName(config[field.key])
                elseif field.type == "number" then
                    valueDisplay = tostring(config[field.key])
                elseif field.type == "peripheral" then
                    valueDisplay = config[field.key]
                else
                    valueDisplay = tostring(config[field.key])
                end
            end

            -- Truncate if needed
            local maxValueLen = width - 6
            if #valueDisplay > maxValueLen then
                valueDisplay = valueDisplay:sub(1, maxValueLen - 3) .. "..."
            end

            monitor.setTextColor(valueColor)
            monitor.setCursorPos(2, y + 1)
            monitor.write("  " .. valueDisplay .. " ")
            monitor.setTextColor(colors.gray)
            monitor.write("[>]")

            table.insert(fieldBounds, {
                y1 = y, y2 = y + 1,
                field = field
            })
        end

        -- Save/Cancel buttons
        local saveY = height - 1
        local cancelY = height

        monitor.setBackgroundColor(colors.green)
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(1, saveY)
        monitor.write(string.rep(" ", width))
        monitor.setCursorPos(math.floor((width - 4) / 2) + 1, saveY)
        monitor.write("Save")

        monitor.setBackgroundColor(colors.red)
        monitor.setCursorPos(1, cancelY)
        monitor.write(string.rep(" ", width))
        monitor.setCursorPos(math.floor((width - 6) / 2) + 1, cancelY)
        monitor.write("Cancel")

        -- Wait for touch
        local event, side, x, y = os.pullEvent("monitor_touch")

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
                            value = item.name,
                            label = prettifyName(item.name) .. " (" .. (item.count or 0) .. ")"
                        })
                    end
                    newValue = ConfigUI.drawPicker(monitor, "Select Item", options, config[field.key], function(opt)
                        return opt.label
                    end)

                elseif field.type == "fluid:id" then
                    local fluids = getAE2Fluids()
                    local options = {}
                    for _, fluid in ipairs(fluids) do
                        table.insert(options, {
                            value = fluid.name,
                            label = prettifyName(fluid.name) .. " (" .. math.floor((fluid.amount or 0) / 1000) .. "B)"
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
                        field.presets
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
                    newValue = ConfigUI.drawPicker(monitor, field.label or field.key, options, config[field.key])
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
