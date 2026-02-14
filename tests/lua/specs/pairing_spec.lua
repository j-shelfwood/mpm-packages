local module_cache = {}

_G.mpm = function(name)
    if not module_cache[name] then
        module_cache[name] = dofile("mpm-packages/" .. name .. ".lua")
    end
    return module_cache[name]
end

local Pairing = mpm("net/Pairing")
local Protocol = mpm("net/Protocol")
local Crypto = mpm("net/Crypto")

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

local function with_stubbed_env(fn, overrides)
    local restore = {}

    for key, value in pairs(overrides) do
        if key ~= "os" then
            restore[key] = _G[key]
            _G[key] = value
        end
    end

    local os_restore = {}
    if overrides.os then
        for name, fn_impl in pairs(overrides.os) do
            os_restore[name] = os[name]
            os[name] = fn_impl
        end
    end

    local ok, err = pcall(fn)

    if overrides.os then
        for name, original in pairs(os_restore) do
            os[name] = original
        end
    end

    for key, original in pairs(restore) do
        _G[key] = original
    end

    if not ok then error(err) end
end

test("Pairing.acceptFromPocket succeeds with signed delivery", function()
    local opened, closed = false, false
    local broadcasts, sends = {}, {}
    local displayCode = nil
    local delivered = false
    local now = 100000

    with_stubbed_env(function()
        local success, secret, zoneId = Pairing.acceptFromPocket({
            onDisplayCode = function(code) displayCode = code end
        })

        assert_true(success)
        assert_eq("secret-abc", secret)
        assert_eq("zone-main", zoneId)
        assert_true(opened)
        assert_true(closed)
        assert_true(#broadcasts >= 1)
        assert_eq(Protocol.MessageType.PAIR_READY, broadcasts[1].msg.type)
        assert_eq(1, #sends)
        assert_eq(Protocol.MessageType.PAIR_COMPLETE, sends[1].msg.type)
    end, {
        peripheral = {
            find = function(kind)
                if kind == "modem" then
                    return { isWireless = function() return true end }
                end
                return nil
            end,
            getName = function() return "left" end,
        },
        rednet = {
            isOpen = function() return false end,
            open = function() opened = true end,
            close = function() closed = true end,
            broadcast = function(msg, protocol)
                table.insert(broadcasts, { msg = msg, protocol = protocol })
            end,
            send = function(id, msg, protocol)
                table.insert(sends, { id = id, msg = msg, protocol = protocol })
            end,
        },
        keys = { q = 16 },
        os = {
            getComputerID = function() return 12 end,
            getComputerLabel = function() return "zone-node" end,
            epoch = function()
                now = now + 100
                return now
            end,
            startTimer = function() return 1 end,
            pullEvent = function()
                if not delivered then
                    delivered = true
                    local deliver = Protocol.createPairDeliver("secret-abc", "zone-main")
                    local signed = Crypto.wrapWith(deliver, displayCode)
                    return "rednet_message", 44, signed, Pairing.PROTOCOL
                end
                return "timer", 1
            end,
        },
    })
end)

test("Pairing.acceptFromPocket handles reject", function()
    local cancelled = nil
    local now = 200000

    with_stubbed_env(function()
        local success = Pairing.acceptFromPocket({
            onCancel = function(reason) cancelled = reason end
        })

        assert_false(success)
        assert_eq("Rejected by pocket", cancelled)
    end, {
        peripheral = {
            find = function() return { isWireless = function() return true end } end,
            getName = function() return "left" end,
        },
        rednet = {
            isOpen = function() return false end,
            open = function() end,
            close = function() end,
            broadcast = function() end,
            send = function() end,
        },
        keys = { q = 16 },
        os = {
            getComputerID = function() return 12 end,
            getComputerLabel = function() return "zone-node" end,
            epoch = function()
                now = now + 100
                return now
            end,
            startTimer = function() return 1 end,
            pullEvent = function()
                return "rednet_message", 44, Protocol.createPairReject("nope"), Pairing.PROTOCOL
            end,
        },
    })
end)

test("Pairing.deliverToPending sends signed payload and completes", function()
    local sent = {}
    local now = 300000
    local ready = Protocol.createPairReady(nil, "Zone A", 21)
    local complete = Protocol.createPairComplete("Zone A")
    local events = {
        { "rednet_message", 21, ready, Pairing.PROTOCOL },
        { "key", 13 },
        { "rednet_message", 21, complete, Pairing.PROTOCOL },
    }

    with_stubbed_env(function()
        local success, paired = Pairing.deliverToPending("swarm-secret", "zone-main", {
            onCodePrompt = function() return "ABCD-EFGH" end,
        }, 5)

        assert_true(success)
        assert_eq("Zone A", paired)
        assert_eq(1, #sent)
        assert_eq(21, sent[1].id)
        assert_true(type(sent[1].msg) == "table" and sent[1].msg.v == 1, "expected signed envelope")
    end, {
        peripheral = {
            find = function() return { isWireless = function() return true end } end,
            getName = function() return "right" end,
        },
        rednet = {
            isOpen = function() return false end,
            open = function() end,
            close = function() end,
            send = function(id, msg, protocol)
                table.insert(sent, { id = id, msg = msg, protocol = protocol })
            end,
        },
        keys = { q = 16, up = 200, down = 208, enter = 13 },
        os = {
            epoch = function()
                now = now + 100
                return now
            end,
            startTimer = function() return 1 end,
            pullEvent = function()
                if #events == 0 then
                    return "timer", 1
                end
                local e = table.remove(events, 1)
                return e[1], e[2], e[3], e[4]
            end,
        },
    })
end)

test("Pairing.deliverToPending rejects short code", function()
    local invalidReasons = {}
    local now = 400000
    local ready = Protocol.createPairReady(nil, "Zone B", 22)
    local events = {
        { "rednet_message", 22, ready, Pairing.PROTOCOL },
        { "key", 13 },
        { "key", 16 },
    }

    with_stubbed_env(function()
        local success = Pairing.deliverToPending("swarm-secret", "zone-b", {
            onCodePrompt = function() return "A" end,
            onCodeInvalid = function(reason) table.insert(invalidReasons, reason) end,
        }, 5)

        assert_false(success)
        assert_eq(1, #invalidReasons)
        assert_eq("Code too short", invalidReasons[1])
    end, {
        peripheral = {
            find = function() return { isWireless = function() return true end } end,
            getName = function() return "right" end,
        },
        rednet = {
            isOpen = function() return false end,
            open = function() end,
            close = function() end,
            send = function() end,
        },
        keys = { q = 16, up = 200, down = 208, enter = 13 },
        os = {
            epoch = function()
                now = now + 100
                return now
            end,
            startTimer = function() return 1 end,
            pullEvent = function()
                if #events == 0 then
                    return "timer", 1
                end
                local e = table.remove(events, 1)
                return e[1], e[2], e[3], e[4]
            end,
        },
    })
end)
