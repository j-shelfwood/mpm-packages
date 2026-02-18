-- TermUI.lua
-- Terminal drawing primitives for ShelfOS apps
-- Provides styled UI components for terminal-based flows
-- Color scheme matches ui/Core.lua for visual consistency with monitor UI

local Core = mpm('ui/Core')
local Keys = mpm('utils/Keys')
local EventUtils = mpm('utils/EventUtils')

local TermUI = {}

-- Screen dimensions (cached on first use)
local screenW, screenH

-- Get screen dimensions (cached)
function TermUI.getSize()
    if not screenW then
        screenW, screenH = term.getSize()
    end
    return screenW, screenH
end

-- Refresh cached dimensions
function TermUI.refreshSize()
    screenW, screenH = term.getSize()
    return screenW, screenH
end

-- Clear screen with black background
function TermUI.clear()
    local w, h = TermUI.getSize()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

-- Draw a full-width colored bar with centered text
-- @param y Row number
-- @param text Text to display (centered)
-- @param bgColor Background color (default: blue)
-- @param fgColor Text color (default: white)
function TermUI.drawBar(y, text, bgColor, fgColor)
    local w = TermUI.getSize()
    bgColor = bgColor or colors.blue
    fgColor = fgColor or colors.white

    term.setCursorPos(1, y)
    term.setBackgroundColor(bgColor)
    term.setTextColor(fgColor)
    term.write(Core.padText(text or "", w, "center"))
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

-- Draw title bar at row 1
-- @param title Title text
-- @param bgColor Optional background color (default: blue)
function TermUI.drawTitleBar(title, bgColor)
    TermUI.drawBar(1, title, bgColor or colors.blue, colors.white)
end

-- Draw status bar at bottom row with key hints
-- @param items Array of {key, label} or single string
function TermUI.drawStatusBar(items)
    local w, h = TermUI.getSize()

    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.write(string.rep(" ", w))

    if type(items) == "string" then
        -- Simple string
        term.setCursorPos(2, h)
        term.write(items)
    elseif type(items) == "table" then
        -- Build "[K] Label [K] Label" string
        local parts = {}
        for _, item in ipairs(items) do
            table.insert(parts, "[" .. item.key:upper() .. "] " .. item.label)
        end
        local menuStr = table.concat(parts, " ")
        local x = math.max(1, math.floor((w - #menuStr) / 2))
        term.setCursorPos(x, h)
        term.write(menuStr)
    end

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

-- Draw a styled menu item with highlighted key
-- @param y Row number
-- @param key Single character key (e.g., "A")
-- @param label Menu item label
-- @param opts Optional: { color, badge, indent }
function TermUI.drawMenuItem(y, key, label, opts)
    opts = opts or {}
    local indent = opts.indent or 2
    local labelColor = opts.color or colors.white
    local badge = opts.badge

    term.setCursorPos(indent, y)
    term.setBackgroundColor(colors.black)

    -- Key bracket: yellow
    term.setTextColor(colors.yellow)
    term.write("[" .. key:upper() .. "]")

    -- Label
    term.setTextColor(labelColor)
    term.write(" " .. label)

    -- Optional badge (e.g., computer count)
    if badge then
        term.setTextColor(colors.lightGray)
        term.write("  " .. badge)
    end

    term.setTextColor(colors.white)
end

-- Draw a horizontal separator line
-- @param y Row number
-- @param color Optional color (default: gray)
function TermUI.drawSeparator(y, color)
    local w = TermUI.getSize()
    term.setCursorPos(1, y)
    term.setBackgroundColor(color or colors.gray)
    term.write(string.rep(" ", w))
    term.setBackgroundColor(colors.black)
end

-- Draw a key-value info line
-- @param y Row number
-- @param label Key text
-- @param value Value text
-- @param valueColor Optional color for value (default: white)
-- @param indent Optional indent (default: 2)
function TermUI.drawInfoLine(y, label, value, valueColor, indent)
    indent = indent or 2
    valueColor = valueColor or colors.white

    term.setCursorPos(indent, y)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)
    term.write(label .. ": ")
    term.setTextColor(valueColor)
    term.write(tostring(value or ""))
    term.setTextColor(colors.white)
end

-- Draw text at position with optional colors
-- @param x Column
-- @param y Row
-- @param text Text string
-- @param fg Foreground color (default: white)
-- @param bg Background color (default: black)
function TermUI.drawText(x, y, text, fg, bg)
    term.setCursorPos(x, y)
    term.setBackgroundColor(bg or colors.black)
    term.setTextColor(fg or colors.white)
    term.write(text)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

-- Draw centered text on a row
-- @param y Row number
-- @param text Text string
-- @param fg Foreground color (default: white)
-- @param bg Background color (default: black)
function TermUI.drawCentered(y, text, fg, bg)
    local w = TermUI.getSize()
    local x = math.max(1, math.floor((w - #text) / 2) + 1)
    TermUI.drawText(x, y, text, fg, bg)
end

-- Draw a progress bar
-- @param y Row number
-- @param label Label text before bar
-- @param percent Fill percentage (0-100)
-- @param opts Optional: { fillColor, emptyColor, indent, barWidth }
function TermUI.drawProgress(y, label, percent, opts)
    opts = opts or {}
    local indent = opts.indent or 2
    local fillColor = opts.fillColor or colors.lime
    local emptyColor = opts.emptyColor or colors.gray
    local w = TermUI.getSize()

    percent = math.max(0, math.min(100, percent or 0))

    term.setCursorPos(indent, y)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)

    if label and #label > 0 then
        term.write(label .. " ")
    end

    local barStart = indent + (label and #label + 1 or 0)
    local pctStr = string.format(" %d%%", percent)
    local barWidth = w - barStart - #pctStr
    local filledWidth = math.floor(barWidth * percent / 100)

    -- Filled portion
    term.setBackgroundColor(fillColor)
    term.write(string.rep(" ", filledWidth))

    -- Empty portion
    term.setBackgroundColor(emptyColor)
    term.write(string.rep(" ", barWidth - filledWidth))

    -- Percentage text
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write(pctStr)
end

-- Draw wrapped text starting at row y
-- @param y Starting row
-- @param text Text to wrap
-- @param fg Foreground color
-- @param indent Left indent (default: 2)
-- @param maxLines Maximum lines to use (default: unlimited)
-- @return Number of lines used
function TermUI.drawWrapped(y, text, fg, indent, maxLines)
    indent = indent or 2
    local w = TermUI.getSize()
    local lineWidth = w - indent - 1
    local lines = 0

    fg = fg or colors.white

    while #text > 0 and (not maxLines or lines < maxLines) do
        local chunk
        if #text <= lineWidth then
            chunk = text
            text = ""
        else
            -- Find last space within lineWidth
            local breakAt = lineWidth
            for i = lineWidth, 1, -1 do
                if text:sub(i, i) == " " then
                    breakAt = i
                    break
                end
            end
            chunk = text:sub(1, breakAt)
            text = text:sub(breakAt + 1)
            -- Trim leading space
            if text:sub(1, 1) == " " then
                text = text:sub(2)
            end
        end

        TermUI.drawText(indent, y + lines, chunk, fg)
        lines = lines + 1
    end

    return lines
end

-- Draw a compact metric line with fixed label color
-- @param x Column
-- @param y Row
-- @param label Metric label
-- @param value Metric value
-- @param valueColor Optional value color
function TermUI.drawMetric(x, y, label, value, valueColor)
    term.setCursorPos(x, y)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)
    term.write((label or "") .. ": ")
    term.setTextColor(valueColor or colors.white)
    term.write(tostring(value or ""))
    term.setTextColor(colors.white)
end

-- Draw an activity light indicator with optional count
-- @param x Column
-- @param y Row
-- @param label Activity label
-- @param lastActivityTs Last activity timestamp in ms
-- @param count Optional cumulative count
-- @param opts Optional: { flashMs, activeColor, idleColor, labelColor, countColor }
function TermUI.drawActivityLight(x, y, label, lastActivityTs, count, opts)
    opts = opts or {}
    local flashMs = opts.flashMs or 700
    local activeColor = opts.activeColor or colors.lime
    local idleColor = opts.idleColor or colors.gray
    local labelColor = opts.labelColor or colors.lightGray
    local countColor = opts.countColor or colors.white

    local now = os.epoch("utc")
    local isActive = lastActivityTs and ((now - lastActivityTs) <= flashMs) or false

    term.setCursorPos(x, y)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write("[")
    term.setBackgroundColor(isActive and activeColor or idleColor)
    term.write(" ")
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write("] ")
    term.setTextColor(labelColor)
    term.write(label or "")

    if count ~= nil then
        term.setTextColor(countColor)
        term.write(" " .. tostring(count))
    end

    term.setTextColor(colors.white)
end

-- Clear a single row
-- @param y Row number
function TermUI.clearLine(y)
    local w = TermUI.getSize()
    term.setCursorPos(1, y)
    term.setBackgroundColor(colors.black)
    term.write(string.rep(" ", w))
end

-- Read text input with styled prompt
-- @param y Row number
-- @param prompt Prompt text
-- @param opts Optional: { indent, promptColor, inputColor }
-- @return Input string or nil if empty
function TermUI.readInput(y, prompt, opts)
    opts = opts or {}
    local indent = opts.indent or 2
    local promptColor = opts.promptColor or colors.lightGray
    local inputColor = opts.inputColor or colors.white

    term.setCursorPos(indent, y)
    term.setBackgroundColor(colors.black)
    term.setTextColor(promptColor)
    term.write(prompt)

    term.setTextColor(inputColor)
    local input = read()

    if input and #input > 0 then
        return input
    end
    return nil
end

-- Wait for a specific key press
-- @param validKeys Table mapping key names to return values, e.g., {q = "quit", a = "add"}
-- @return The mapped value for the pressed key
function TermUI.waitForKey(validKeys)
    while true do
        local _, keyCode = EventUtils.pullEvent("key")
        local keyName = keys.getName(keyCode)

        if keyName then
            keyName = keyName:lower()

            -- Check direct match
            if validKeys[keyName] then
                return validKeys[keyName]
            end

            -- Check number keys
            local num = Keys.getNumber(keyName)
            if num and validKeys[tostring(num)] then
                return validKeys[tostring(num)]
            end
        end
    end
end

-- Wait for any key press
-- @return key name
function TermUI.waitForAnyKey()
    local _, keyCode = EventUtils.pullEvent("key")
    return keys.getName(keyCode)
end

-- Draw an animated scanning/loading indicator
-- Call repeatedly with incrementing frame counter
-- @param y Row number
-- @param text Label text
-- @param frame Frame counter (0, 1, 2, ...)
-- @param indent Optional indent
function TermUI.drawSpinner(y, text, frame, indent)
    indent = indent or 2
    local spinChars = { "|", "/", "-", "\\" }
    local char = spinChars[(frame % #spinChars) + 1]

    term.setCursorPos(indent, y)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow)
    term.write(char .. " ")
    term.setTextColor(colors.white)
    term.write(text)

    -- Clear rest of line
    local w = TermUI.getSize()
    local remaining = w - indent - 2 - #text
    if remaining > 0 then
        term.write(string.rep(" ", remaining))
    end
end

return TermUI
