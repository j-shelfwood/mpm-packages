-- PairingScreen.lua
-- Shared UI for displaying pairing codes on monitors
-- Used by Kernel.lua and tools/pair_accept.lua

local PairingScreen = {}
local Config = mpm('shelfos/core/Config')

-- Calculate optimal text scale based on monitor size
-- @param w Current width
-- @param h Current height
-- @return Recommended scale (1-4)
local function calculateScale(w, h)
    if w >= 80 and h >= 40 then
        return 4
    elseif w >= 60 and h >= 30 then
        return 3
    elseif w >= 40 and h >= 20 then
        return 2
    end
    return 1
end

-- Draw pairing code on a monitor as large as possible
-- @param mon Monitor peripheral
-- @param code Pairing code (e.g., "ABCD-EFGH")
-- @param label Computer label to display
function PairingScreen.drawCode(mon, code, label)
    local w, h = mon.getSize()

    -- Determine best text scale (larger monitors get larger text)
    local scale = calculateScale(w, h)
    mon.setTextScale(scale)
    w, h = mon.getSize()  -- Re-get size after scale change

    mon.setBackgroundColor(colors.blue)
    mon.clear()

    -- Title
    mon.setTextColor(colors.white)
    local title = "PAIRING CODE"
    mon.setCursorPos(math.floor((w - #title) / 2) + 1, 2)
    mon.write(title)

    -- Code (centered, highlighted)
    mon.setBackgroundColor(colors.white)
    mon.setTextColor(colors.black)
    local codeY = math.floor(h / 2)
    local codeX = math.floor((w - #code) / 2) + 1

    -- Draw background box for code
    for y = codeY - 1, codeY + 1 do
        mon.setCursorPos(codeX - 2, y)
        mon.write(string.rep(" ", #code + 4))
    end

    -- Draw code
    mon.setCursorPos(codeX, codeY)
    mon.write(code)

    -- Instructions
    mon.setBackgroundColor(colors.blue)
    mon.setTextColor(colors.yellow)
    local instr = "Enter on pocket"
    mon.setCursorPos(math.floor((w - #instr) / 2) + 1, h - 2)
    mon.write(instr)

    -- Label at bottom
    mon.setTextColor(colors.lightGray)
    local labelText = label:sub(1, w - 2)
    mon.setCursorPos(math.floor((w - #labelText) / 2) + 1, h - 1)
    mon.write(labelText)
end

-- Draw pairing code on all connected monitors
-- @param code Pairing code
-- @param label Computer label
-- @param monitorNames Optional canonical monitor names
-- @return Table of monitor names that were drawn to
function PairingScreen.drawOnAllMonitors(code, label, monitorNames)
    local drawn = {}
    local discovered = monitorNames or Config.discoverMonitors()

    for _, name in ipairs(discovered) do
        local mon = peripheral.wrap(name)
        if mon then
            PairingScreen.drawCode(mon, code, label)
            table.insert(drawn, name)
        end
    end

    return drawn
end

-- Clear pairing display from a single monitor
-- @param mon Monitor peripheral
function PairingScreen.clear(mon)
    mon.setTextScale(1)
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
end

-- Clear pairing display from multiple monitors by name
-- @param monitorNames Table of monitor peripheral names
function PairingScreen.clearAll(monitorNames)
    for _, name in ipairs(monitorNames) do
        local mon = peripheral.wrap(name)
        if mon then
            PairingScreen.clear(mon)
        end
    end
end

return PairingScreen
