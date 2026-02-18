return function(h)
    h:test("pairing contract: pocket payload survives crypto envelope", function()
        local Protocol = mpm("net/Protocol")
        local Crypto = mpm("net/Crypto")
        local Pairing = mpm("net/Pairing")

        local displayCode = Pairing.generateCode()
        local creds = {
            swarmSecret = "swarm-secret-example-1234567890",
            computerId = "computer_42",
            swarmFingerprint = "FP-TEST-1234",
            computerSecret = "computer-secret-abcdef"
        }

        local deliver = Protocol.createPairDeliver(creds.swarmSecret, creds.computerId)
        deliver.data.credentials = creds

        local envelope = Crypto.wrapWith(deliver, displayCode)
        local decoded, err = Crypto.unwrapWith(envelope, displayCode)

        h:assert_not_nil(decoded, "Failed to decode envelope: " .. tostring(err))
        h:assert_eq(Protocol.MessageType.PAIR_DELIVER, decoded.type, "Decoded type mismatch")
        h:assert_eq(creds.swarmSecret, decoded.data.secret, "swarmSecret mismatch")
        h:assert_eq(creds.computerId, decoded.data.computerId, "computerId mismatch")
        h:assert_eq(creds.swarmFingerprint, decoded.data.credentials.swarmFingerprint, "fingerprint mismatch")
    end)

    h:test("pairing contract: shelfos and shelfos-swarm share protocol constant", function()
        local Pairing = mpm("net/Pairing")
        local addComputerPath = h.workspace .. "/shelfos-swarm/screens/AddComputer.lua"
        local pairAcceptPath = h.workspace .. "/shelfos/tools/pair_accept.lua"

        local addComputerSrc, errA = h:read_file(addComputerPath)
        local pairAcceptSrc, errB = h:read_file(pairAcceptPath)
        h:assert_not_nil(addComputerSrc, "Failed to read AddComputer.lua: " .. tostring(errA))
        h:assert_not_nil(pairAcceptSrc, "Failed to read pair_accept.lua: " .. tostring(errB))

        h:assert_contains(addComputerSrc, "shelfos_pair", "AddComputer should target pairing protocol")
        h:assert_contains(pairAcceptSrc, "Pairing.acceptFromPocket", "pair_accept should use Pairing module")
        h:assert_eq("shelfos_pair", Pairing.PROTOCOL, "Pairing.PROTOCOL unexpectedly changed")
    end)

    h:test("pairing contract: code key candidates normalize user input formats", function()
        local Pairing = mpm("net/Pairing")

        local candidates = Pairing.getCodeKeyCandidates("  abcd 1234  ")
        local seen = {}
        for _, candidate in ipairs(candidates) do
            seen[candidate] = true
        end

        h:assert_true(seen["ABCD1234"] == true, "Expected compact code candidate")
        h:assert_true(seen["ABCD-1234"] == true, "Expected dashed code candidate")
    end)
end
