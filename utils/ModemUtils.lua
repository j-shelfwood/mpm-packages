-- ModemUtils.lua
-- Modem detection utilities with wireless-first preference
-- Solves: computers with both wired and ender modems picking the wrong one

local ModemUtils = {}

-- Find a modem with wireless preference
-- Wired modems return false for isWireless()
-- Wireless and Ender modems return true for isWireless()
-- @param preferWireless Prefer wireless/ender over wired (default: true)
-- @return modem peripheral, modem name, modem type ("wireless" or "wired")
function ModemUtils.find(preferWireless)
    if preferWireless == nil then preferWireless = true end

    local modems = {peripheral.find("modem")}

    local wired = nil
    local wiredName = nil
    local wireless = nil
    local wirelessName = nil

    for _, m in ipairs(modems) do
        local name = peripheral.getName(m)
        if m.isWireless() then
            wireless = m
            wirelessName = name
        else
            wired = m
            wiredName = name
        end
    end

    -- Select based on preference
    if preferWireless and wireless then
        return wireless, wirelessName, "wireless"
    elseif wired then
        return wired, wiredName, "wired"
    elseif wireless then
        return wireless, wirelessName, "wireless"
    end

    return nil, nil, nil
end

-- Find wireless modem only (strict)
-- @return modem peripheral, modem name, or nil
function ModemUtils.findWireless()
    local modems = {peripheral.find("modem", function(name, modem)
        return modem.isWireless()
    end)}

    if #modems > 0 then
        return modems[1], peripheral.getName(modems[1]), "wireless"
    end

    return nil, nil, nil
end

-- Check if any wireless modem exists
-- @return boolean
function ModemUtils.hasWireless()
    local m = ModemUtils.findWireless()
    return m ~= nil
end

-- Check if any modem exists
-- @return boolean
function ModemUtils.hasAny()
    local m = peripheral.find("modem")
    return m ~= nil
end

-- Open a modem with wireless preference
-- Closes other modems to prevent duplicate message reception
-- @param preferWireless Prefer wireless/ender over wired (default: true)
-- @return success, modemName, modemType
function ModemUtils.open(preferWireless)
    local modem, name, mtype = ModemUtils.find(preferWireless)

    if not modem then
        return false, nil, nil
    end

    -- Close all other modems to prevent duplicate reception
    local allModems = {peripheral.find("modem")}
    for _, m in ipairs(allModems) do
        local mName = peripheral.getName(m)
        if mName ~= name and rednet.isOpen(mName) then
            rednet.close(mName)
        end
    end

    rednet.open(name)
    return true, name, mtype
end

-- Close a modem by name
-- @param name Modem peripheral name
function ModemUtils.close(name)
    if name and rednet.isOpen(name) then
        rednet.close(name)
    end
end

return ModemUtils
