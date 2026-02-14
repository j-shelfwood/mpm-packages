-- MenuViewSelector.lua
-- View selection UI for monitor configuration
-- Provides scrollable list with keyboard/touch navigation
-- Extracted from Menu.lua for maintainability

local Controller = mpm('ui/Controller')
local Keys = mpm('utils/Keys')

local MenuViewSelector = {}

-- Show view selection for a specific monitor
-- @param monitor Monitor instance
-- @param availableViews Array of view names
-- @param target Term-like object (default: term.current())
-- @return Selected view name or nil if cancelled
function MenuViewSelector.show(monitor, availableViews, target)
    target = target or term.current()

    if #availableViews == 0 then
        Controller.showInfo(target, "Select View", {
            "",
            "No views available.",
            "",
            "Check that view modules are installed."
        })
        return nil
    end

    -- Find current view index
    local currentView = monitor:getViewName()
    local currentIndex = 1

    for i, view in ipairs(availableViews) do
        if view == currentView then
            currentIndex = i
            break
        end
    end

    -- Build options with current marker
    local options = {}
    for i, view in ipairs(availableViews) do
        local marker = (view == currentView) and " *" or ""
        table.insert(options, {
            value = view,
            label = view .. marker
        })
    end

    -- Custom event loop that handles N/P shortcuts
    local width, height = target.getSize()
    local isMonitor, monitorName = Controller.isMonitor(target)
    local scrollOffset = 0

    -- Format function
    local function formatView(opt)
        return opt.label
    end

    -- Get value
    local function getValue(opt)
        if type(opt) == "table" then
            return opt.value
        end
        return opt
    end

    -- Calculate layout
    local function getLayout()
        local titleHeight = 3  -- Title + monitor name + blank
        local footerHeight = 2
        local startY = titleHeight + 1
        local maxVisible = height - startY - footerHeight
        return startY, math.max(1, maxVisible)
    end

    -- Initial scroll
    local startY, maxVisible = getLayout()
    if currentIndex > maxVisible then
        scrollOffset = currentIndex - maxVisible
    end

    -- Render function
    local function render()
        Controller.clear(target)
        Controller.drawTitle(target, "Select View")

        -- Monitor name
        target.setTextColor(colors.lightGray)
        target.setCursorPos(2, 3)
        local monName = monitor:getName()
        if #monName > width - 4 then
            monName = monName:sub(1, width - 7) .. "..."
        end
        target.write("Monitor: " .. monName)

        local startY, maxVisible = getLayout()

        -- Options list
        local visibleCount = math.min(maxVisible, #options - scrollOffset)

        for i = 1, visibleCount do
            local optIndex = i + scrollOffset
            local opt = options[optIndex]

            if opt then
                local y = startY + i - 1
                local label = formatView(opt)
                local value = getValue(opt)
                local isSelected = value == currentView

                -- Number prefix
                local prefix = ""
                if optIndex <= 9 then
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

        -- Footer with shortcuts
        target.setTextColor(colors.yellow)
        target.setCursorPos(2, height - 1)
        target.write("[N] Next  [P] Prev  [B] Back")

        target.setBackgroundColor(colors.black)
        target.setTextColor(colors.white)
    end

    -- Event loop
    while true do
        render()

        local event, p1, p2, p3 = os.pullEvent()

        if event == "key" then
            local keyName = keys.getName(p1)

            if keyName then
                keyName = keyName:lower()

                -- Back
                if keyName == "b" then
                    return nil
                end

                -- Next/Previous
                if keyName == "n" then
                    local nextIndex = currentIndex + 1
                    if nextIndex > #availableViews then nextIndex = 1 end
                    return availableViews[nextIndex]
                elseif keyName == "p" then
                    local prevIndex = currentIndex - 1
                    if prevIndex < 1 then prevIndex = #availableViews end
                    return availableViews[prevIndex]
                end

                -- Number selection (1-9)
                local num = Keys.getNumber(keyName)
                if num and num >= 1 and num <= #availableViews then
                    return availableViews[num]
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

            -- Back (bottom area)
            if p3 >= height - 1 then
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
                    if optIndex >= 1 and optIndex <= #availableViews then
                        return availableViews[optIndex]
                    end
                end
            end
        end
    end
end

return MenuViewSelector
