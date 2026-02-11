-- Terminal.lua
-- Terminal window management for ShelfOS
-- Isolates log output from menu bar using CC:Tweaked windows

local Terminal = {}

-- Window references
local native = nil
local logWindow = nil
local menuWindow = nil
local initialized = false

-- Initialize terminal windows
function Terminal.init()
    if initialized then return end

    native = term.native()
    local w, h = native.getSize()

    -- Log window: everything except bottom row
    logWindow = window.create(native, 1, 1, w, h - 1, true)

    -- Menu window: bottom row only
    menuWindow = window.create(native, 1, h, w, 1, true)

    -- Redirect default output to log window
    term.redirect(logWindow)

    initialized = true
end

-- Get the log window (for general output)
function Terminal.getLogWindow()
    Terminal.init()
    return logWindow
end

-- Get the menu window (for menu bar)
function Terminal.getMenuWindow()
    Terminal.init()
    return menuWindow
end

-- Get native terminal
function Terminal.getNative()
    return term.native()
end

-- Redirect to log window (default)
function Terminal.redirectToLog()
    Terminal.init()
    term.redirect(logWindow)
end

-- Redirect to menu window
function Terminal.redirectToMenu()
    Terminal.init()
    term.redirect(menuWindow)
end

-- Clear the log window
function Terminal.clearLog()
    Terminal.init()
    local old = term.redirect(logWindow)
    term.clear()
    term.setCursorPos(1, 1)
    term.redirect(old)
end

-- Clear the menu window
function Terminal.clearMenu()
    Terminal.init()
    local old = term.redirect(menuWindow)
    term.clear()
    term.setCursorPos(1, 1)
    term.redirect(old)
end

-- Clear everything
function Terminal.clearAll()
    Terminal.clearLog()
    Terminal.clearMenu()
end

-- Write to log window
function Terminal.log(text)
    Terminal.init()
    local old = term.redirect(logWindow)
    print(text)
    term.redirect(old)
end

-- Draw menu bar
function Terminal.drawMenu(items)
    Terminal.init()

    local old = term.redirect(menuWindow)
    local w, _ = menuWindow.getSize()

    -- Build menu string
    local parts = {}
    for _, item in ipairs(items) do
        table.insert(parts, "[" .. item.key:upper() .. "] " .. item.label)
    end
    local menuStr = table.concat(parts, "  ")

    -- Clear and draw centered
    menuWindow.setBackgroundColor(colors.gray)
    menuWindow.clear()
    menuWindow.setTextColor(colors.white)

    local x = math.floor((w - #menuStr) / 2) + 1
    menuWindow.setCursorPos(x, 1)
    menuWindow.write(menuStr)

    term.redirect(old)
end

-- Show a full-screen dialog (temporarily takes over)
-- Returns to normal terminal layout when done
function Terminal.showDialog(drawFunc)
    Terminal.init()

    -- Save current redirect
    local old = term.current()

    -- Use native terminal for dialog
    term.redirect(native)
    term.clear()
    term.setCursorPos(1, 1)

    -- Run the dialog draw function
    local result = drawFunc()

    -- Restore windows
    term.redirect(logWindow)

    -- Redraw menu
    return result
end

-- Resize windows (call if terminal size changes)
function Terminal.resize()
    if not initialized then return end

    local w, h = native.getSize()

    -- Recreate windows with new size
    logWindow = window.create(native, 1, 1, w, h - 1, true)
    menuWindow = window.create(native, 1, h, w, 1, true)

    term.redirect(logWindow)
end

-- Run a function with output suppressed
function Terminal.suppressOutput(func, ...)
    Terminal.init()

    -- Create a null terminal that discards everything
    local nullTerm = {
        write = function() end,
        blit = function() end,
        clear = function() end,
        clearLine = function() end,
        getCursorPos = function() return 1, 1 end,
        setCursorPos = function() end,
        getCursorBlink = function() return false end,
        setCursorBlink = function() end,
        getSize = function() return 51, 19 end,
        scroll = function() end,
        isColour = function() return true end,
        isColor = function() return true end,
        setTextColour = function() end,
        setTextColor = function() end,
        getTextColour = function() return colors.white end,
        getTextColor = function() return colors.white end,
        setBackgroundColour = function() end,
        setBackgroundColor = function() end,
        getBackgroundColour = function() return colors.black end,
        getBackgroundColor = function() return colors.black end,
    }

    local old = term.redirect(nullTerm)
    local results = {pcall(func, ...)}
    term.redirect(old)

    if results[1] then
        return table.unpack(results, 2)
    else
        return nil
    end
end

return Terminal
