-- Controller.lua
-- Unified control abstraction for terminal and monitor input/output
-- Bridges keyboard menu navigation with touch UI components

local Core = mpm('ui/Core')

local Controller = {}

-- Detect if target is a monitor peripheral or terminal
-- @param target Term-like object (term.native() or monitor peripheral)
-- @return boolean isMonitor, string|nil peripheralName
function Controller.isMonitor(target)
    -- Try to get peripheral name - monitors have this, terminal doesn't
    local ok, name = pcall(peripheral.getName, target)
    if ok and name then
        return true, name
    end
    return false, nil
end

-- Clear target with consistent styling
-- @param target Term-like object
function Controller.clear(target)
    local isMonitor = Controller.isMonitor(target)
    if isMonitor then
        Core.clear(target)
    else
        target.setBackgroundColor(colors.black)
        target.setTextColor(colors.white)
        target.clear()
        target.setCursorPos(1, 1)
    end
end

-- Draw a title bar
-- @param target Term-like object
-- @param title Title text
function Controller.drawTitle(target, title)
    local width = target.getSize()
    local isMonitor = Controller.isMonitor(target)

    if isMonitor then
        Core.drawBar(target, 1, title, Core.COLORS.titleBar, Core.COLORS.titleText)
    else
        target.setBackgroundColor(colors.blue)
        target.setTextColor(colors.white)
        target.setCursorPos(1, 1)
        local padding = math.floor((width - #title) / 2)
        target.write(string.rep(" ", padding) .. title .. string.rep(" ", width - padding - #title))
        target.setBackgroundColor(colors.black)
        target.setTextColor(colors.white)
        target.setCursorPos(1, 3)
    end
end

-- Show informational dialog with multiple lines
-- @param target Term-like object
-- @param title Dialog title
-- @param lines Array of strings to display
-- @param opts Options: { footer = "Press any key..." }
function Controller.showInfo(target, title, lines, opts)
    opts = opts or {}
    local footer = opts.footer or "Press any key to continue..."
    local width, height = target.getSize()
    local isMonitor, monitorName = Controller.isMonitor(target)

    Controller.clear(target)
    Controller.drawTitle(target, title)

    -- Content lines
    local startY = 3
    target.setTextColor(colors.white)

    for i, line in ipairs(lines) do
        if startY + i - 1 < height - 1 then
            target.setCursorPos(2, startY + i - 1)
            local displayLine = line
            if #displayLine > width - 2 then
                displayLine = displayLine:sub(1, width - 5) .. "..."
            end
            target.write(displayLine)
        end
    end

    -- Footer
    target.setTextColor(colors.lightGray)
    target.setCursorPos(2, height)
    target.write(footer)
    target.setTextColor(colors.white)

    -- Wait for input
    if isMonitor then
        while true do
            local event, side = os.pullEvent()
            if event == "monitor_touch" and side == monitorName then
                break
            elseif event == "key" then
                break
            end
        end
    else
        os.pullEvent("key")
    end
end

-- Show confirmation dialog
-- @param target Term-like object
-- @param title Dialog title
-- @param message Message to display
-- @param opts Options: { confirmKey = "y", cancelKey = "n" }
-- @return boolean confirmed
function Controller.showConfirm(target, title, message, opts)
    opts = opts or {}
    local confirmKey = opts.confirmKey or "y"
    local cancelKey = opts.cancelKey or "n"
    local width, height = target.getSize()
    local isMonitor, monitorName = Controller.isMonitor(target)

    Controller.clear(target)
    Controller.drawTitle(target, title)

    -- Message
    local msgY = math.floor(height / 2)
    target.setTextColor(colors.white)
    target.setCursorPos(2, msgY)

    local displayMsg = message
    if #displayMsg > width - 4 then
        displayMsg = displayMsg:sub(1, width - 7) .. "..."
    end
    target.write(displayMsg)

    -- Prompt
    target.setTextColor(colors.yellow)
    target.setCursorPos(2, msgY + 2)
    target.write("(" .. confirmKey:upper() .. "/" .. cancelKey:upper() .. ")")
    target.setTextColor(colors.white)

    if isMonitor then
        -- Draw touch buttons
        local buttonY = msgY + 4
        local okX = math.floor(width / 2) - 6
        local cancelX = math.floor(width / 2) + 2

        target.setBackgroundColor(colors.green)
        target.setCursorPos(okX, buttonY)
        target.write(" Yes ")

        target.setBackgroundColor(colors.red)
        target.setCursorPos(cancelX, buttonY)
        target.write(" No ")

        target.setBackgroundColor(colors.black)

        -- Wait for touch or key
        while true do
            local event, p1, p2, p3 = os.pullEvent()

            if event == "monitor_touch" and p1 == monitorName then
                -- Check button bounds
                if p3 == buttonY then
                    if p2 >= okX and p2 < okX + 5 then
                        return true
                    elseif p2 >= cancelX and p2 < cancelX + 5 then
                        return false
                    end
                end
            elseif event == "key" then
                local keyName = keys.getName(p1)
                if keyName then
                    keyName = keyName:lower()
                    if keyName == confirmKey then
                        return true
                    elseif keyName == cancelKey then
                        return false
                    end
                end
            end
        end
    else
        -- Terminal: just wait for Y/N key
        while true do
            local event, key = os.pullEvent("key")
            local keyName = keys.getName(key)
            if keyName then
                keyName = keyName:lower()
                if keyName == confirmKey then
                    return true
                elseif keyName == cancelKey then
                    return false
                end
            end
        end
    end
end

-- Show list selection dialog with keyboard shortcuts
-- @param target Term-like object
-- @param title Dialog title
-- @param options Array of {label, value} or strings
-- @param opts Options: { selected, showNumbers, showBack, formatFn, shortcuts }
-- @return selected value or nil if cancelled
function Controller.selectFromList(target, title, options, opts)
    opts = opts or {}
    local width, height = target.getSize()
    local isMonitor, monitorName = Controller.isMonitor(target)

    local selected = opts.selected
    local showNumbers = opts.showNumbers ~= false
    local showBack = opts.showBack ~= false
    local formatFn = opts.formatFn or function(opt)
        if type(opt) == "table" then
            return opt.label or opt.name or tostring(opt.value or opt)
        end
        return tostring(opt)
    end
    local shortcuts = opts.shortcuts or {}  -- Additional shortcuts like {n = "next", p = "prev"}

    local scrollOffset = 0

    -- Get value from option
    local function getValue(opt)
        if type(opt) == "table" then
            return opt.value or opt.name or opt
        end
        return opt
    end

    -- Find selected index
    local function findSelectedIndex()
        for i, opt in ipairs(options) do
            if getValue(opt) == selected then
                return i
            end
        end
        return 1
    end

    -- Calculate visible area
    local function getLayout()
        local titleHeight = 2
        local footerHeight = showBack and 2 or 1
        local startY = titleHeight + 1
        local maxVisible = height - startY - footerHeight
        return startY, math.max(1, maxVisible)
    end

    -- Render function
    local function render()
        Controller.clear(target)
        Controller.drawTitle(target, title)

        local startY, maxVisible = getLayout()

        -- Options list
        local visibleCount = math.min(maxVisible, #options - scrollOffset)

        for i = 1, visibleCount do
            local optIndex = i + scrollOffset
            local opt = options[optIndex]

            if opt then
                local y = startY + i - 1
                local label = formatFn(opt)
                local value = getValue(opt)
                local isSelected = value == selected

                -- Number prefix
                local prefix = ""
                if showNumbers and optIndex <= 9 then
                    prefix = "[" .. optIndex .. "] "
                else
                    prefix = "    "
                end

                -- Truncate if needed
                local maxLen = width - #prefix - 2
                if #label > maxLen then
                    label = label:sub(1, maxLen - 3) .. "..."
                end

                if isSelected then
                    target.setBackgroundColor(colors.gray)
                    target.setTextColor(colors.white)
                    target.setCursorPos(1, y)
                    target.write(string.rep(" ", width))
                    target.setCursorPos(2, y)
                    target.write(prefix .. label)
                else
                    target.setBackgroundColor(colors.black)
                    target.setTextColor(colors.lightGray)
                    target.setCursorPos(2, y)
                    target.write(prefix .. label)
                end
            end
        end

        -- Scroll indicators
        target.setBackgroundColor(colors.black)
        target.setTextColor(colors.gray)

        if scrollOffset > 0 then
            target.setCursorPos(width, startY)
            target.write("^")
        end

        if scrollOffset + maxVisible < #options then
            target.setCursorPos(width, startY + maxVisible - 1)
            target.write("v")
        end

        -- Footer with back option
        if showBack then
            target.setTextColor(colors.yellow)
            target.setCursorPos(2, height)
            target.write("[B] Back")
        end

        target.setBackgroundColor(colors.black)
        target.setTextColor(colors.white)
    end

    -- Initial scroll to selection
    local selectedIndex = findSelectedIndex()
    local _, maxVisible = getLayout()
    if selectedIndex > maxVisible then
        scrollOffset = selectedIndex - maxVisible
    end

    -- Event loop
    while true do
        render()

        local event, p1, p2, p3 = os.pullEvent()

        if event == "key" then
            local keyName = keys.getName(p1)

            if keyName then
                keyName = keyName:lower()

                -- Check custom shortcuts first
                if shortcuts[keyName] then
                    return shortcuts[keyName]
                end

                -- Back
                if keyName == "b" and showBack then
                    return nil
                end

                -- Number selection (1-9)
                -- keys.getName returns "one", "two", etc. - need to map to numbers
                local keyToNum = {
                    one = 1, two = 2, three = 3, four = 4, five = 5,
                    six = 6, seven = 7, eight = 8, nine = 9,
                    numpad1 = 1, numpad2 = 2, numpad3 = 3, numpad4 = 4, numpad5 = 5,
                    numpad6 = 6, numpad7 = 7, numpad8 = 8, numpad9 = 9
                }
                local num = keyToNum[keyName]
                if num and num >= 1 and num <= #options then
                    return getValue(options[num])
                end

                -- Arrow keys for scrolling
                if keyName == "up" and scrollOffset > 0 then
                    scrollOffset = scrollOffset - 1
                elseif keyName == "down" and scrollOffset + maxVisible < #options then
                    scrollOffset = scrollOffset + 1
                end
            end

        elseif event == "monitor_touch" and p1 == monitorName then
            local startY, maxVisible = getLayout()

            -- Back button (bottom row)
            if showBack and p3 == height then
                return nil
            end

            -- Scroll indicators
            if p2 == width then
                if p3 == startY and scrollOffset > 0 then
                    scrollOffset = scrollOffset - 1
                elseif p3 == startY + maxVisible - 1 and scrollOffset + maxVisible < #options then
                    scrollOffset = scrollOffset + 1
                end
            else
                -- Option selection
                if p3 >= startY and p3 < startY + maxVisible then
                    local optIndex = (p3 - startY + 1) + scrollOffset
                    if optIndex >= 1 and optIndex <= #options then
                        return getValue(options[optIndex])
                    end
                end
            end
        end
    end
end

-- Get text input (terminal only, monitors show placeholder)
-- @param target Term-like object
-- @param prompt Prompt text
-- @param opts Options: { default }
-- @return string input or nil if cancelled
function Controller.getInput(target, prompt, opts)
    opts = opts or {}
    local isMonitor = Controller.isMonitor(target)

    if isMonitor then
        -- Monitors don't support text input well
        -- Show message directing to terminal
        Controller.showInfo(target, "Input Required", {
            "Text input not supported on monitors.",
            "Use the terminal keyboard."
        })
        return nil
    end

    target.setTextColor(colors.white)
    write(prompt)

    local input = read()

    if input and #input > 0 then
        return input
    elseif opts.default then
        return opts.default
    end

    return nil
end

return Controller
