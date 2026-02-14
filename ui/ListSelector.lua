-- ListSelector.lua
-- Scrollable list selection UI for terminal/monitor
-- Supports keyboard navigation, touch, and custom shortcuts
-- Extracted from Controller.lua for maintainability

local Keys = mpm('utils/Keys')

local ListSelector = {}

-- Check if target is a monitor
local function isMonitor(target)
    if target.setTextScale then
        local ok = pcall(function() target.setTextScale(target.getTextScale()) end)
        if ok then
            return true, peripheral.getName(target)
        end
    end
    return false, nil
end

-- Clear and reset colors
local function clear(target)
    target.setBackgroundColor(colors.black)
    target.setTextColor(colors.white)
    target.clear()
    target.setCursorPos(1, 1)
end

-- Draw title bar
local function drawTitle(target, title)
    local width = target.getSize()
    target.setBackgroundColor(colors.gray)
    target.setTextColor(colors.white)
    target.setCursorPos(1, 1)
    target.clearLine()
    target.setCursorPos(2, 1)
    target.write(title)
    target.setBackgroundColor(colors.black)
end

-- Show scrollable list selection
-- @param target Term-like object
-- @param title Dialog title
-- @param options Array of {label, value} or strings
-- @param opts Options: { selected, showNumbers, showBack, formatFn, shortcuts }
-- @return selected value or nil if cancelled
function ListSelector.show(target, title, options, opts)
    opts = opts or {}
    local width, height = target.getSize()
    local isMonitorTarget, monitorName = isMonitor(target)

    local selected = opts.selected
    local showNumbers = opts.showNumbers ~= false
    local showBack = opts.showBack ~= false
    local formatFn = opts.formatFn or function(opt)
        if type(opt) == "table" then
            return opt.label or opt.name or tostring(opt.value or opt)
        end
        return tostring(opt)
    end
    local shortcuts = opts.shortcuts or {}

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
        clear(target)
        drawTitle(target, title)

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
                local num = Keys.getNumber(keyName)
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

return ListSelector
