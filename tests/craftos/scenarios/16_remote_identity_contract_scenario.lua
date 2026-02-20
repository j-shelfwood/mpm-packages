return function(h)
    local function list_contains(list, needle)
        for _, value in ipairs(list or {}) do
            if value == needle then
                return true
            end
        end
        return false
    end

    h:test("remote identity: duplicate peripheral names across hosts remain collision-safe", function()
        local PeripheralClient = mpm("net/PeripheralClient")
        local client = PeripheralClient.new(nil)

        client:handleAnnounce(10, {
            data = {
                computerId = "node_10",
                computerName = "Node 10",
                peripherals = {
                    { name = "left", type = "energy_detector", methods = {} }
                }
            }
        })

        client:handleAnnounce(20, {
            data = {
                computerId = "node_20",
                computerName = "Node 20",
                peripherals = {
                    { name = "left", type = "energy_detector", methods = {} }
                }
            }
        })

        h:assert_eq(2, client:getCount(), "Expected both remotes with duplicate names to be retained")

        local names = client:getNames()
        h:assert_true(list_contains(names, "10::left"), "Expected host-qualified key for first host")
        h:assert_true(list_contains(names, "20::left"), "Expected host-qualified key for second host")

        local preferred = client:wrap("left")
        h:assert_not_nil(preferred, "Expected bare-name alias to resolve to deterministic preferred host")
        h:assert_eq(10, preferred._hostId, "Bare-name alias should prefer lower numeric hostId")

        local specific = client:wrap("20::left")
        h:assert_not_nil(specific, "Expected host-qualified key to resolve to exact host")
        h:assert_eq(20, specific._hostId, "Host-qualified key should target matching hostId")
    end)

    h:test("remote identity: host re-announce replaces stale peripherals from same host", function()
        local PeripheralClient = mpm("net/PeripheralClient")
        local client = PeripheralClient.new(nil)

        client:handleAnnounce(42, {
            data = {
                computerId = "node_42",
                computerName = "Node 42",
                peripherals = {
                    { name = "left", type = "energy_detector", methods = {} },
                    { name = "right", type = "energy_detector", methods = {} }
                }
            }
        })

        h:assert_true(client:isPresent("42::left"), "Expected left to exist after first announce")
        h:assert_true(client:isPresent("42::right"), "Expected right to exist after first announce")

        client:handleAnnounce(42, {
            data = {
                computerId = "node_42",
                computerName = "Node 42",
                peripherals = {
                    { name = "right", type = "energy_detector", methods = {} }
                }
            }
        })

        h:assert_false(client:isPresent("42::left"), "Expected stale peripheral removed after host re-announce")
        h:assert_true(client:isPresent("42::right"), "Expected current peripheral retained after host re-announce")
        h:assert_eq(1, client:getCount(), "Expected exactly one remote after replacement announce")
    end)

    h:test("remote fallback: local type mismatch does not mask valid remote hasType", function()
        local RemotePeripheral = mpm("net/RemotePeripheral")

        local originalPeripheral = _G.peripheral
        local originalClient = RemotePeripheral.getClient()

        _G.peripheral = {
            isPresent = function(name)
                return name == "left"
            end,
            hasType = function(name, pType)
                if name == "left" then
                    return pType == "monitor"
                end
                return false
            end,
            getType = function(name)
                if name == "left" then return "monitor" end
                return nil
            end,
            wrap = function()
                return nil
            end,
            getMethods = function()
                return nil
            end,
            call = function()
                return nil
            end,
            getNames = function()
                return { "left" }
            end,
            find = function()
                return nil
            end
        }

        local fakeClient = {
            hasType = function(_, name, pType)
                if name == "left" and pType == "energy_detector" then
                    return true
                end
                return nil
            end
        }
        RemotePeripheral.setClient(fakeClient)

        h:assert_true(
            RemotePeripheral.hasType("left", "energy_detector"),
            "Expected remote hasType to win when local side exists but has mismatched type"
        )

        RemotePeripheral.setClient(nil)
        h:assert_false(
            RemotePeripheral.hasType("left", "energy_detector"),
            "Expected local mismatch to resolve false when no remote candidate exists"
        )

        RemotePeripheral.setClient(originalClient)
        _G.peripheral = originalPeripheral
    end)

    h:test("protocol: PERIPH_LIST includes optional host metadata for first-contact labeling", function()
        local Protocol = mpm("net/Protocol")
        local request = { requestId = "req_123" }

        local msg = Protocol.createPeriphList(
            request,
            { { name = "left", type = "energy_detector", methods = {} } },
            "computer_7",
            "Node Seven"
        )

        h:assert_eq(Protocol.MessageType.PERIPH_LIST, msg.type, "Unexpected protocol type")
        h:assert_eq("req_123", msg.requestId, "Response requestId should match source request")
        h:assert_eq("computer_7", msg.data.computerId, "Expected metadata computerId in PERIPH_LIST response")
        h:assert_eq("Node Seven", msg.data.computerName, "Expected metadata computerName in PERIPH_LIST response")
    end)
end
