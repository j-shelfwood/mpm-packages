local root = _G.TEST_ROOT or "."
local Text = dofile(root .. "/utils/Text.lua")

local function assert_eq(expected, actual, message)
    if expected ~= actual then
        error((message or "values differ") .. string.format(" (expected=%s actual=%s)", tostring(expected), tostring(actual)))
    end
end

local function assert_true(value, message)
    if not value then
        error(message or "expected true")
    end
end

test("Text.formatNumber thresholds", function()
    assert_eq("999", Text.formatNumber(999))
    assert_eq("1.0K", Text.formatNumber(1000))
    assert_eq("1.0M", Text.formatNumber(1000000))
end)

test("Text.prettifyName converts namespaced ID", function()
    assert_eq("Diamond ore", Text.prettifyName("minecraft:diamond_ore"))
end)

test("Text.truncateMiddle keeps max length", function()
    local out = Text.truncateMiddle("abcdefghijk", 7)
    assert_eq(7, #out)
    assert_true(out:find("%.%.%.") ~= nil)
end)

test("Text.formatFluidAmount units", function()
    assert_eq("500mB", Text.formatFluidAmount(500))
    assert_eq("1.0B", Text.formatFluidAmount(1000))
    assert_eq("1.0K B", Text.formatFluidAmount(1000000))
end)
