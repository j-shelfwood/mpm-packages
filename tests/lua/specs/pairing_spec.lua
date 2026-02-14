local root = _G.TEST_ROOT or "."
local module_cache = {}

_G.mpm = function(name)
    if not module_cache[name] then
        module_cache[name] = dofile(root .. "/" .. name .. ".lua")
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

-- =============================================================================
-- GAP TESTS: Timeout handling
-- =============================================================================

test("Pairing.acceptFromPocket times out after TOKEN_VALIDITY", function()
    local now = 500000
    local timerCount = 0
    local statusMessages = {}

    with_stubbed_env(function()
        local success, secret, zoneId = Pairing.acceptFromPocket({
            onDisplayCode = function() end,
            onStatus = function(msg) table.insert(statusMessages, msg) end,
        })

        assert_false(success, "Should return false on timeout")
        assert_true(secret == nil, "Secret should be nil on timeout")
        assert_true(zoneId == nil, "ZoneId should be nil on timeout")
        -- Should have status messages showing countdown
        assert_true(#statusMessages > 0, "Should have status updates")
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
                -- Jump 5 seconds each call to quickly exceed TOKEN_VALIDITY (60s)
                now = now + 5000
                return now
            end,
            startTimer = function() return 1 end,
            pullEvent = function()
                timerCount = timerCount + 1
                -- Only return timer events to simulate no response
                return "timer", 1
            end,
        },
    })
end)

test("Pairing.deliverToPending times out with no zones", function()
    local now = 600000
    local timerCount = 0

    with_stubbed_env(function()
        local success, paired = Pairing.deliverToPending("swarm-secret", "zone-id", {}, 2)

        assert_false(success, "Should return false on timeout")
        assert_true(paired == nil, "Paired should be nil")
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
                now = now + 500  -- 0.5 seconds per call
                return now
            end,
            startTimer = function() return 1 end,
            pullEvent = function()
                timerCount = timerCount + 1
                return "timer", 1
            end,
        },
    })
end)

-- =============================================================================
-- GAP TESTS: User cancellation
-- =============================================================================

test("Pairing.acceptFromPocket handles user pressing q to cancel", function()
    local now = 700000
    local cancelReason = nil
    local broadcasts = {}
    local keyPressed = false

    with_stubbed_env(function()
        local success = Pairing.acceptFromPocket({
            onDisplayCode = function() end,
            onCancel = function(reason) cancelReason = reason end,
        })

        assert_false(success, "Should return false when cancelled")
        assert_eq("User cancelled", cancelReason)
        -- Should have broadcast PAIR_REJECT
        local foundReject = false
        for _, b in ipairs(broadcasts) do
            if b.msg and b.msg.type == Protocol.MessageType.PAIR_REJECT then
                foundReject = true
                break
            end
        end
        assert_true(foundReject, "Should broadcast PAIR_REJECT on cancel")
    end, {
        peripheral = {
            find = function() return { isWireless = function() return true end } end,
            getName = function() return "left" end,
        },
        rednet = {
            isOpen = function() return false end,
            open = function() end,
            close = function() end,
            broadcast = function(msg, protocol)
                table.insert(broadcasts, { msg = msg, protocol = protocol })
            end,
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
                if not keyPressed then
                    keyPressed = true
                    return "key", 16  -- keys.q
                end
                return "timer", 1
            end,
        },
    })
end)

test("Pairing.deliverToPending handles user pressing q to cancel", function()
    local now = 800000
    local cancelCalled = false

    with_stubbed_env(function()
        local success = Pairing.deliverToPending("swarm-secret", "zone-id", {
            onCancel = function() cancelCalled = true end,
        }, 30)

        assert_false(success)
        assert_true(cancelCalled, "onCancel should be called")
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
                return "key", 16  -- keys.q immediately
            end,
        },
    })
end)

-- =============================================================================
-- GAP TESTS: Modem error handling
-- =============================================================================

test("Pairing.acceptFromPocket handles no modem gracefully", function()
    with_stubbed_env(function()
        local success, secret, zoneId, _, errMsg = Pairing.acceptFromPocket({})

        assert_false(success, "Should return false with no modem")
        assert_true(secret == nil)
        assert_true(zoneId == nil)
    end, {
        peripheral = {
            find = function() return nil end,  -- No modem
            getName = function() return nil end,
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
            epoch = function() return 900000 end,
            startTimer = function() return 1 end,
            pullEvent = function() return "timer", 1 end,
        },
    })
end)

test("Pairing.deliverToPending handles no modem gracefully", function()
    with_stubbed_env(function()
        local success, paired, errMsg = Pairing.deliverToPending("secret", "zone", {}, 5)

        assert_false(success)
        assert_true(paired == nil)
        assert_eq("No modem found", errMsg)
    end, {
        peripheral = {
            find = function() return nil end,
            getName = function() return nil end,
        },
        rednet = {
            isOpen = function() return false end,
            open = function() end,
            close = function() end,
            send = function() end,
        },
        keys = { q = 16 },
        os = {
            epoch = function() return 1000000 end,
            startTimer = function() return 1 end,
            pullEvent = function() return "timer", 1 end,
        },
    })
end)

test("Pairing.acceptFromPocket handles modem already open", function()
    local now = 1100000
    local opened, closed = false, false
    local delivered = false
    local displayCode = nil

    with_stubbed_env(function()
        local success, secret, zoneId = Pairing.acceptFromPocket({
            onDisplayCode = function(code) displayCode = code end,
        })

        assert_true(success)
        assert_false(opened, "Should not call open when already open")
        assert_false(closed, "Should not call close when was already open")
    end, {
        peripheral = {
            find = function() return { isWireless = function() return true end } end,
            getName = function() return "left" end,
        },
        rednet = {
            isOpen = function() return true end,  -- Already open
            open = function() opened = true end,
            close = function() closed = true end,
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
                if not delivered then
                    delivered = true
                    local deliver = Protocol.createPairDeliver("secret", "zone")
                    local signed = Crypto.wrapWith(deliver, displayCode)
                    return "rednet_message", 44, signed, Pairing.PROTOCOL
                end
                return "timer", 1
            end,
        },
    })
end)

-- =============================================================================
-- GAP TESTS: Credential format variations
-- =============================================================================

test("Pairing.acceptFromPocket extracts legacy simple credentials", function()
    local now = 1200000
    local delivered = false
    local displayCode = nil

    with_stubbed_env(function()
        local success, secret, zoneId = Pairing.acceptFromPocket({
            onDisplayCode = function(code) displayCode = code end,
        })

        assert_true(success)
        assert_eq("legacy-secret", secret)
        assert_eq("legacy-zone", zoneId)
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
                if not delivered then
                    delivered = true
                    -- Legacy format: secret and zoneId directly in data (no credentials sub-object)
                    local deliver = Protocol.createPairDeliver("legacy-secret", "legacy-zone")
                    -- Remove credentials to simulate legacy format
                    deliver.data.credentials = nil
                    local signed = Crypto.wrapWith(deliver, displayCode)
                    return "rednet_message", 44, signed, Pairing.PROTOCOL
                end
                return "timer", 1
            end,
        },
    })
end)

test("Pairing.acceptFromPocket extracts full SwarmAuthority credentials", function()
    local now = 1300000
    local delivered = false
    local displayCode = nil

    with_stubbed_env(function()
        local success, secret, zoneId = Pairing.acceptFromPocket({
            onDisplayCode = function(code) displayCode = code end,
        })

        assert_true(success)
        assert_eq("swarm-master-secret", secret)
        assert_eq("zone-from-creds", zoneId)
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
                if not delivered then
                    delivered = true
                    -- Full SwarmAuthority format with credentials sub-object
                    local deliver = Protocol.createPairDeliver("ignored", "ignored")
                    deliver.data.credentials = {
                        swarmSecret = "swarm-master-secret",
                        zoneId = "zone-from-creds",
                        swarmId = "swarm-123",
                        swarmFingerprint = "FP-ABC"
                    }
                    local signed = Crypto.wrapWith(deliver, displayCode)
                    return "rednet_message", 44, signed, Pairing.PROTOCOL
                end
                return "timer", 1
            end,
        },
    })
end)

-- =============================================================================
-- GAP TESTS: State machine edge cases
-- =============================================================================

test("Pairing.deliverToPending tracks multiple zones correctly", function()
    local now = 1400000
    local readyCallCount = 0
    local events = {
        { "rednet_message", 21, Protocol.createPairReady(nil, "Zone A", 21), Pairing.PROTOCOL },
        { "rednet_message", 22, Protocol.createPairReady(nil, "Zone B", 22), Pairing.PROTOCOL },
        { "rednet_message", 23, Protocol.createPairReady(nil, "Zone C", 23), Pairing.PROTOCOL },
        { "key", 16 },  -- Cancel after seeing 3 zones
    }

    with_stubbed_env(function()
        Pairing.deliverToPending("secret", "zone", {
            onReady = function(pair) readyCallCount = readyCallCount + 1 end,
            onCancel = function() end,
        }, 10)

        assert_eq(3, readyCallCount, "Should have called onReady for each unique zone")
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
                if #events == 0 then return "timer", 1 end
                local e = table.remove(events, 1)
                return e[1], e[2], e[3], e[4]
            end,
        },
    })
end)

test("Pairing.deliverToPending cleans up stale zones after 15 seconds", function()
    local now = 1500000
    local readyCallCount = 0
    local eventIndex = 0
    local events = {
        { "rednet_message", 21, Protocol.createPairReady(nil, "Zone A", 21), Pairing.PROTOCOL },
        -- After this, time will jump 16 seconds
        { "key", 16 },  -- Cancel
    }

    with_stubbed_env(function()
        Pairing.deliverToPending("secret", "zone", {
            onReady = function() readyCallCount = readyCallCount + 1 end,
            onCancel = function() end,
        }, 30)

        -- Zone should be added then cleaned up
        assert_eq(1, readyCallCount, "Zone should have been detected initially")
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
                eventIndex = eventIndex + 1
                if eventIndex > 1 then
                    -- Jump 16 seconds to trigger stale cleanup
                    now = now + 16000
                else
                    now = now + 100
                end
                return now
            end,
            startTimer = function() return 1 end,
            pullEvent = function()
                if #events == 0 then return "timer", 1 end
                local e = table.remove(events, 1)
                return e[1], e[2], e[3], e[4]
            end,
        },
    })
end)

test("Pairing.deliverToPending navigation with up/down keys", function()
    local now = 1600000
    local sent = {}
    local events = {
        { "rednet_message", 21, Protocol.createPairReady(nil, "Zone A", 21), Pairing.PROTOCOL },
        { "rednet_message", 22, Protocol.createPairReady(nil, "Zone B", 22), Pairing.PROTOCOL },
        { "key", 208 },  -- down to Zone B
        { "key", 13 },   -- enter to select Zone B
        { "rednet_message", 22, Protocol.createPairComplete("Zone B"), Pairing.PROTOCOL },
    }

    with_stubbed_env(function()
        local success, paired = Pairing.deliverToPending("secret", "zone", {
            onCodePrompt = function() return "ABCD-EFGH" end,
        }, 10)

        assert_true(success)
        assert_eq("Zone B", paired)
        -- Should have sent to Zone B (id=22), not Zone A (id=21)
        assert_eq(1, #sent)
        assert_eq(22, sent[1].id, "Should send to Zone B after navigation")
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
                if #events == 0 then return "timer", 1 end
                local e = table.remove(events, 1)
                return e[1], e[2], e[3], e[4]
            end,
        },
    })
end)

test("Pairing.deliverToPending wrong code results in no response callback", function()
    local now = 1700000
    local invalidReasons = {}
    local events = {
        { "rednet_message", 21, Protocol.createPairReady(nil, "Zone A", 21), Pairing.PROTOCOL },
        { "key", 13 },   -- enter to select
        -- No PAIR_COMPLETE response (zone rejected wrong code)
        { "key", 16 },   -- cancel after timeout
    }

    with_stubbed_env(function()
        local success = Pairing.deliverToPending("secret", "zone", {
            onCodePrompt = function() return "WRONG-CODE" end,
            onCodeInvalid = function(reason) table.insert(invalidReasons, reason) end,
            onCancel = function() end,
        }, 10)

        assert_false(success)
        assert_eq(1, #invalidReasons)
        assert_eq("No response - check code", invalidReasons[1])
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
                now = now + 1000  -- 1 second per call to hit 5s confirmation timeout
                return now
            end,
            startTimer = function() return 1 end,
            pullEvent = function()
                if #events == 0 then return "timer", 1 end
                local e = table.remove(events, 1)
                return e[1], e[2], e[3], e[4]
            end,
        },
    })
end)

test("Pairing.acceptFromPocket ignores invalid signature silently", function()
    local now = 1800000
    local delivered = false
    local attemptsBeforeValid = 0
    local displayCode = nil

    with_stubbed_env(function()
        local success, secret = Pairing.acceptFromPocket({
            onDisplayCode = function(code) displayCode = code end,
        })

        assert_true(success)
        assert_eq("valid-secret", secret)
        assert_true(attemptsBeforeValid >= 1, "Should have received invalid attempt first")
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
                attemptsBeforeValid = attemptsBeforeValid + 1
                if attemptsBeforeValid == 1 then
                    -- First: attacker sends with wrong code
                    local deliver = Protocol.createPairDeliver("attacker-secret", "zone")
                    local wrongSigned = Crypto.wrapWith(deliver, "WRONG-CODE")
                    return "rednet_message", 99, wrongSigned, Pairing.PROTOCOL
                elseif not delivered then
                    delivered = true
                    -- Second: legitimate pocket sends with correct code
                    local deliver = Protocol.createPairDeliver("valid-secret", "zone")
                    local signed = Crypto.wrapWith(deliver, displayCode)
                    return "rednet_message", 44, signed, Pairing.PROTOCOL
                end
                return "timer", 1
            end,
        },
    })
end)

test("Pairing.acceptFromPocket re-broadcasts every 3 seconds", function()
    local now = 1900000
    local broadcastCount = 0
    local callCount = 0
    local delivered = false
    local displayCode = nil

    with_stubbed_env(function()
        Pairing.acceptFromPocket({
            onDisplayCode = function(code) displayCode = code end,
        })

        assert_true(broadcastCount >= 3, "Should have re-broadcast multiple times")
    end, {
        peripheral = {
            find = function() return { isWireless = function() return true end } end,
            getName = function() return "left" end,
        },
        rednet = {
            isOpen = function() return false end,
            open = function() end,
            close = function() end,
            broadcast = function()
                broadcastCount = broadcastCount + 1
            end,
            send = function() end,
        },
        keys = { q = 16 },
        os = {
            getComputerID = function() return 12 end,
            getComputerLabel = function() return "zone-node" end,
            epoch = function()
                callCount = callCount + 1
                -- Simulate 4 seconds per timer event (triggers re-broadcast)
                now = now + 4000
                return now
            end,
            startTimer = function() return 1 end,
            pullEvent = function()
                callCount = callCount + 1
                -- After several re-broadcasts, deliver valid response
                if callCount > 10 and not delivered then
                    delivered = true
                    local deliver = Protocol.createPairDeliver("secret", "zone")
                    local signed = Crypto.wrapWith(deliver, displayCode)
                    return "rednet_message", 44, signed, Pairing.PROTOCOL
                end
                return "timer", 1
            end,
        },
    })
end)
