return function(h)
    h:test("pairing runtime: acceptFromPocket consumes signed deliver", function()
        local Protocol = mpm("net/Protocol")
        local Crypto = mpm("net/Crypto")
        local Pairing = mpm("net/Pairing")
        local ModemUtils = mpm("utils/ModemUtils")

        local originalOpen = ModemUtils.open
        local originalGenerateCode = Pairing.generateCode
        local originalRednet = rednet

        local sent = {}
        rednet = {
            broadcast = function(message, protocol)
                table.insert(sent, { kind = "broadcast", message = message, protocol = protocol })
            end,
            send = function(id, message, protocol)
                table.insert(sent, { kind = "send", id = id, message = message, protocol = protocol })
            end
        }

        ModemUtils.open = function()
            return true, "back", "wireless"
        end
        Pairing.generateCode = function()
            return "ABCD-1234"
        end

        local deliver = Protocol.createPairDeliver("runtime-secret-123456", "computer_88")
        local envelope = Crypto.wrapWith(deliver, "ABCD-1234")
        os.queueEvent("rednet_message", 88, envelope, Pairing.PROTOCOL)

        local ok, success, secret, computerId = pcall(function()
            return Pairing.acceptFromPocket({})
        end)

        rednet = originalRednet
        ModemUtils.open = originalOpen
        Pairing.generateCode = originalGenerateCode

        h:assert_true(ok, "acceptFromPocket crashed")
        h:assert_true(success, "acceptFromPocket should succeed")
        h:assert_eq("runtime-secret-123456", secret, "Secret mismatch")
        h:assert_eq("computer_88", computerId, "ComputerId mismatch")
        h:assert_true(#sent >= 2, "Expected broadcast and completion send")
    end)

    h:test("pairing runtime: deliverToPending drives enter-select flow", function()
        local Protocol = mpm("net/Protocol")
        local Pairing = mpm("net/Pairing")
        local ModemUtils = mpm("utils/ModemUtils")

        local originalOpen = ModemUtils.open
        local originalRednet = rednet

        local sent = {}
        rednet = {
            send = function(id, message, protocol)
                table.insert(sent, { id = id, message = message, protocol = protocol })
                return true
            end,
            broadcast = function() return true end
        }

        ModemUtils.open = function()
            return true, "back", "wireless"
        end

        local ready = Protocol.createPairReady(nil, "Target Computer", 77)
        local complete = Protocol.createPairComplete("Target Computer")

        os.queueEvent("rednet_message", 77, ready, Pairing.PROTOCOL)
        os.queueEvent("key", keys.enter)
        os.queueEvent("rednet_message", 77, complete, Pairing.PROTOCOL)

        local ok, success, paired = pcall(function()
            return Pairing.deliverToPending("deliver-secret-xyz", "computer_77", {
                onCodePrompt = function()
                    return "WXYZ-5678"
                end
            }, 2)
        end)

        rednet = originalRednet
        ModemUtils.open = originalOpen

        h:assert_true(ok, "deliverToPending crashed")
        h:assert_true(success, "deliverToPending should succeed")
        h:assert_eq("Target Computer", paired, "Unexpected paired label")
        h:assert_true(#sent >= 1, "Expected at least one rednet.send")
    end)
end
