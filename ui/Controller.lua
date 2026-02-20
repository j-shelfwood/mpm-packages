-- Controller.lua
-- Unified control abstraction for terminal and monitor input/output
-- Bridges keyboard menu navigation with touch UI components
-- Uses os.pullEvent directly - each monitor runs in its own coroutine with parallel API
--
-- Split modules:
--   ListSelector.lua - Scrollable list selection UI

local Core = mpm('ui/Core')
local Keys = mpm('utils/Keys')
local ListSelector = mpm('ui/ListSelector')
local EventLoop = mpm('ui/EventLoop')

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
            local kind = EventLoop.waitForTouchOrKey(monitorName)
            if kind == "key" or kind == "touch" or kind == "detach" then
                break
            end
        end
    else
        EventLoop.waitForKey()
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
    local isMonitor, monitorName = Controller.isMonitor(target)

    local function render()
        local width, height = target.getSize()
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
        return width, height, msgY
    end

    if isMonitor then
        -- Wait for touch or key
        while true do
            local width, _, msgY = render()
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

            local kind, p1, p2 = EventLoop.waitForTouchOrKey(monitorName)

            if kind == "touch" then
                -- Check button bounds
                if p2 == buttonY then
                    if p1 >= okX and p1 < okX + 5 then
                        return true
                    elseif p1 >= cancelX and p1 < cancelX + 5 then
                        return false
                    end
                end
            elseif kind == "key" then
                local keyName = keys.getName(p1)
                if keyName then
                    keyName = keyName:lower()
                    if keyName == confirmKey then
                        return true
                    elseif keyName == cancelKey then
                        return false
                    end
                end
            elseif kind == "resize" then
                -- Re-render on next loop iteration.
            elseif kind == "detach" then
                return false
            end
        end
    else
        -- Terminal: just wait for Y/N key
        render()
        while true do
            local keyCode = EventLoop.waitForKey()
            local keyName = keys.getName(keyCode)
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
-- Delegates to ListSelector module
-- @param target Term-like object
-- @param title Dialog title
-- @param options Array of {label, value} or strings
-- @param opts Options: { selected, showNumbers, showBack, formatFn, shortcuts }
-- @return selected value or nil if cancelled
function Controller.selectFromList(target, title, options, opts)
    return ListSelector.show(target, title, options, opts)
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
