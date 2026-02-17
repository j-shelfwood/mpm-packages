return function(h)
    local function with_pairing_overrides(h, overrides, fn)
        h:with_overrides(_G, {
            rednet = overrides.rednet,
        }, function()
            h:with_overrides(os, {
                epoch = overrides.epoch,
                startTimer = overrides.startTimer,
                cancelTimer = overrides.cancelTimer,
                pullEvent = overrides.pullEvent,
            }, fn)
        end)
    end

    h:test("pairing lifecycle: stale pending computers are cleaned before selection", function()
        local Pairing = mpm("net/Pairing")
        local Protocol = mpm("net/Protocol")
        local ModemUtils = mpm("utils/ModemUtils")

        local originalOpen = ModemUtils.open
        ModemUtils.open = function()
            return true, "back", "wireless"
        end

        local sent = {}
        local fakeNow = 0
        local promptCalls = 0
        local events = {
            { now = 0, event = { "rednet_message", 41, Protocol.createPairReady(nil, "Stale Node", 41), Pairing.PROTOCOL } },
            { now = 16001, event = { "key", keys.enter } },
            { now = 16002, event = { "key", keys.q } }
        }
        local cursor = 0

        with_pairing_overrides(h, {
            rednet = {
                send = function(id, message, protocol)
                    sent[#sent + 1] = { id = id, message = message, protocol = protocol }
                    return true
                end,
                broadcast = function() return true end
            },
            epoch = function()
                local nextEvent = events[cursor + 1]
                if nextEvent and nextEvent.now > fakeNow then
                    return nextEvent.now
                end
                return fakeNow
            end,
            startTimer = function()
                return 1
            end,
            cancelTimer = function() end,
            pullEvent = function()
                cursor = cursor + 1
                local nextEvent = events[cursor]
                if nextEvent then
                    fakeNow = nextEvent.now
                    return unpack(nextEvent.event)
                end
                fakeNow = fakeNow + 1
                return "key", keys.q
            end
        }, function()
            local ok, paired = Pairing.deliverToPending("secret-1", "computer_41", {
                onCodePrompt = function()
                    promptCalls = promptCalls + 1
                    return "ABCD-1234"
                end
            }, 3)

            h:assert_false(ok, "deliverToPending should cancel when stale entry is cleaned")
            h:assert_true(paired == nil, "No computer should be paired")
        end)

        ModemUtils.open = originalOpen

        h:assert_eq(0, promptCalls, "Stale pair should be removed before code prompt")
        h:assert_eq(0, #sent, "No PAIR_DELIVER should be sent for stale pair")
    end)

    h:test("pairing lifecycle: retry after wrong code can still succeed", function()
        local Pairing = mpm("net/Pairing")
        local Protocol = mpm("net/Protocol")
        local ModemUtils = mpm("utils/ModemUtils")

        local originalOpen = ModemUtils.open
        ModemUtils.open = function()
            return true, "back", "wireless"
        end

        local sent = {}
        local invalidReasons = {}
        local fakeNow = 0
        local enteredCodes = { "BAD-0000", "GOOD-1111" }
        local events = {
            { now = 0, event = { "rednet_message", 77, Protocol.createPairReady(nil, "Retry Node", 77), Pairing.PROTOCOL } },
            { now = 100, event = { "key", keys.enter } },
            { now = 6200, event = { "timer", 1 } },
            { now = 6300, event = { "rednet_message", 77, Protocol.createPairReady(nil, "Retry Node", 77), Pairing.PROTOCOL } },
            { now = 6400, event = { "key", keys.enter } },
            { now = 6450, event = { "rednet_message", 77, Protocol.createPairComplete("Retry Node"), Pairing.PROTOCOL } }
        }
        local cursor = 0

        with_pairing_overrides(h, {
            rednet = {
                send = function(id, message, protocol)
                    sent[#sent + 1] = { id = id, message = message, protocol = protocol }
                    return true
                end,
                broadcast = function() return true end
            },
            epoch = function()
                return fakeNow
            end,
            startTimer = function()
                return 1
            end,
            cancelTimer = function() end,
            pullEvent = function()
                cursor = cursor + 1
                local nextEvent = events[cursor]
                if nextEvent then
                    fakeNow = nextEvent.now
                    return unpack(nextEvent.event)
                end
                fakeNow = fakeNow + 1
                return "key", keys.q
            end
        }, function()
            local ok, paired = Pairing.deliverToPending("secret-2", "computer_77", {
                onCodePrompt = function()
                    return table.remove(enteredCodes, 1)
                end,
                onCodeInvalid = function(reason)
                    invalidReasons[#invalidReasons + 1] = reason
                end
            }, 8)

            h:assert_true(ok, "Second pairing attempt should succeed")
            h:assert_eq("Retry Node", paired, "Unexpected paired computer label")
        end)

        ModemUtils.open = originalOpen

        h:assert_true(#sent >= 2, "Expected two PAIR_DELIVER attempts")
        h:assert_true(#invalidReasons >= 1, "Expected wrong code path to report invalid code")
    end)

    h:test("swarm lifecycle: revoke and re-pair rotates credentials", function()
        local SwarmAuthority = mpm("shelfos-swarm/core/SwarmAuthority")

        if fs.exists("/swarm_registry.dat") then fs.delete("/swarm_registry.dat") end
        if fs.exists("/swarm_identity.dat") then fs.delete("/swarm_identity.dat") end

        local authority = SwarmAuthority.new()
        local created = authority:createSwarm("Lifecycle Swarm")
        h:assert_true(created, "Expected swarm creation to succeed")

        local firstCreds = authority:issueCredentials("node_1", "Node One")
        h:assert_not_nil(firstCreds, "Initial credentials missing")
        h:assert_true(authority:isAuthorized("node_1"), "Node should be active after first issue")

        local revoked = authority:revokeComputer("node_1")
        h:assert_true(revoked, "Expected revoke to succeed")
        h:assert_false(authority:isAuthorized("node_1"), "Revoked node should no longer be authorized")

        local secondCreds = authority:issueCredentials("node_1", "Node One Repaired")
        h:assert_not_nil(secondCreds, "Re-pair credentials missing")
        h:assert_true(authority:isAuthorized("node_1"), "Node should be active after re-pair")
        h:assert_true(secondCreds.computerSecret ~= firstCreds.computerSecret, "Re-pair should rotate computer secret")

        authority:removeComputer("node_1")
        h:assert_true(authority:getComputer("node_1") == nil, "Removed node should no longer exist")

        authority:deleteSwarm()
    end)
end
