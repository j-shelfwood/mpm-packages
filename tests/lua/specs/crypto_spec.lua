local Crypto = dofile("mpm-packages/net/Crypto.lua")

local function assert_true(value, message)
    if not value then
        error(message or "expected true")
    end
end

local function assert_false(value, message)
    if value then
        error(message or "expected false")
    end
end

local function assert_eq(expected, actual, message)
    if expected ~= actual then
        error((message or "values differ") .. string.format(" (expected=%s actual=%s)", tostring(expected), tostring(actual)))
    end
end

test("Crypto.setSecret enforces minimum length", function()
    local ok = pcall(Crypto.setSecret, "short")
    assert_false(ok)
end)

test("Crypto.sign/verify roundtrip", function()
    Crypto.clearSecret()
    Crypto.setSecret("1234567890abcdef")

    local envelope = Crypto.sign({ type = "ping", count = 3 })
    local ok, data, err = Crypto.verify(envelope)
    assert_true(ok, err)
    assert_eq("ping", data.type)
    assert_eq(3, data.count)
end)

test("Crypto.verify blocks nonce replay", function()
    Crypto.clearSecret()
    Crypto.setSecret("fedcba0987654321")

    local envelope = Crypto.sign({ id = 1 })
    local ok1 = select(1, Crypto.verify(envelope))
    local ok2, _, err2 = Crypto.verify(envelope)

    assert_true(ok1)
    assert_false(ok2)
    assert_eq("Duplicate nonce (replay attack)", err2)
end)

test("Crypto.signWith/verifyWith roundtrip", function()
    local envelope = Crypto.signWith({ hello = "world" }, "paircode")
    local ok, data, err = Crypto.verifyWith(envelope, "paircode")
    assert_true(ok, err)
    assert_eq("world", data.hello)
end)
