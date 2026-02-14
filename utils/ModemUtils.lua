-- ModemUtils.lua
-- Modem detection utilities with ender-first preference
-- Solves: computers with both wired and ender modems picking the wrong one
--
-- CC:Tweaked modem types:
--   - Wired modem: isWireless()=false, used for monitor/peripheral connections
--   - Wireless modem: isWireless()=true, limited range
--   - Ender modem: isWireless()=true, unlimited range (cross-dimensional)
--
-- We cannot distinguish wireless from ender via API, but for swarm networking
-- we assume isWireless()=true means ender modem (swarm requirement).

local ModemUtils = {}

-- Find a modem with ender/wireless preference
-- Wired modems return false for isWireless()
-- Wireless and Ender modems return true for isWireless()
-- @param preferEnder Prefer ender/wireless over wired (default: true)
-- @return modem peripheral, modem name, modem type ("ender" or "wired")
function ModemUtils.find(preferEnder)
    if preferEnder == nil then preferEnder = true end

    local modems = {peripheral.find("modem")}

    local wired = nil
    local wiredName = nil
    local ender = nil  -- Could be wireless or ender, we assume ender for swarm
    local enderName = nil

    for _, m in ipairs(modems) do
        local name = peripheral.getName(m)
        if m.isWireless() then
            ender = m
            enderName = name
        else
            wired = m
            wiredName = name
        end
    end

    -- Select based on preference
    if preferEnder and ender then
        return ender, enderName, "ender"
    elseif wired then
        return wired, wiredName, "wired"
    elseif ender then
        return ender, enderName, "ender"
    end

    return nil, nil, nil
end

-- Find ender/wireless modem only (strict)
-- @return modem peripheral, modem name, or nil
function ModemUtils.findEnder()
    local modems = {peripheral.find("modem", function(name, modem)
        return modem.isWireless()
    end)}

    if #modems > 0 then
        return modems[1], peripheral.getName(modems[1]), "ender"
    end

    return nil, nil, nil
end

-- Check if any ender/wireless modem exists
-- @return boolean
function ModemUtils.hasEnder()
    local m = ModemUtils.findEnder()
    return m ~= nil
end

-- Legacy aliases for compatibility
ModemUtils.findWireless = ModemUtils.findEnder
ModemUtils.hasWireless = ModemUtils.hasEnder

-- Check if any modem exists
-- @return boolean
function ModemUtils.hasAny()
    local m = peripheral.find("modem")
    return m ~= nil
end

-- Open a modem with ender preference
-- Closes other modems to prevent duplicate message reception
-- @param preferEnder Prefer ender/wireless over wired (default: true)
-- @return success, modemName, modemType
function ModemUtils.open(preferEnder)
    local modem, name, mtype = ModemUtils.find(preferEnder)

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
