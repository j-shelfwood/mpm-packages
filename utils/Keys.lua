-- Keys.lua
-- Shared key mapping utilities for CC:Tweaked
-- keys.getName() returns "one", "two", etc. - this provides numeric mapping

local Keys = {}

-- Map key names to numbers (for number row and numpad)
-- Used because keys.getName(keys.one) returns "one", not "1"
Keys.keyToNum = {
    one = 1, two = 2, three = 3, four = 4, five = 5,
    six = 6, seven = 7, eight = 8, nine = 9, zero = 0,
    numpad1 = 1, numpad2 = 2, numpad3 = 3, numpad4 = 4, numpad5 = 5,
    numpad6 = 6, numpad7 = 7, numpad8 = 8, numpad9 = 9, numpad0 = 0
}

-- Get numeric value from key name
-- @param keyName Key name from keys.getName()
-- @return number or nil
function Keys.getNumber(keyName)
    if not keyName then return nil end
    return Keys.keyToNum[keyName:lower()]
end

-- Check if a key is a number key (0-9)
-- @param keyName Key name from keys.getName()
-- @return boolean
function Keys.isNumber(keyName)
    return Keys.getNumber(keyName) ~= nil
end

-- Common navigation key checks
function Keys.isUp(keyName)
    return keyName == "up"
end

function Keys.isDown(keyName)
    return keyName == "down"
end

function Keys.isLeft(keyName)
    return keyName == "left"
end

function Keys.isRight(keyName)
    return keyName == "right"
end

function Keys.isEnter(keyName)
    return keyName == "enter" or keyName == "numpadenter"
end

function Keys.isBack(keyName)
    return keyName == "b" or keyName == "backspace"
end

function Keys.isEscape(keyName)
    return keyName == "escape"
end

return Keys
