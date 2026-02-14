-- Multi-Computer Simulation Test
-- Tests pairing flow between simulated zone and pocket computers
-- Run with: craftos --headless --id <N> --mount-ro /workspace=<path> --exec "..."

local WORKSPACE = "/workspace"

-- Determine computer role based on ID
local computerId = os.getComputerID()
local ROLE = computerId < 10 and "pocket" or "zone"

-- Setup mpm loader
local module_cache = {}
_G.mpm = function(name)
    if not module_cache[name] then
        local path = WORKSPACE .. "/" .. name .. ".lua"
        if not fs.exists(path) then
            error("Module not found: " .. name)
        end
        module_cache[name] = dofile(path)
    end
    return module_cache[name]
end

-- Load modules
local Protocol = mpm("net/Protocol")
local Crypto = mpm("net/Crypto")
local Pairing = mpm("net/Pairing")

print("=== Multi-Computer Pairing Test ===")
print(string.format("Computer ID: %d, Role: %s", computerId, ROLE))
print("")

if ROLE == "zone" then
    -- Zone computer: broadcast PAIR_READY and wait for pocket
    print("[ZONE] Opening modem...")

    -- Find any modem (simulated in headless mode)
    -- In headless mode without peripherals, we simulate the flow
    print("[ZONE] Generating display code...")
    local displayCode = Pairing.generateCode()
    print("[ZONE] Display code: " .. displayCode)

    print("[ZONE] Creating PAIR_READY message...")
    local ready = Protocol.createPairReady(nil, "Test Zone", computerId)
    print("[ZONE] Type: " .. tostring(ready.type))
    print("[ZONE] Label: " .. tostring(ready.data.label))

    -- Simulate receiving signed PAIR_DELIVER
    print("")
    print("[ZONE] Simulating PAIR_DELIVER reception...")

    local swarmSecret = Crypto.generateSecret()
    local deliver = Protocol.createPairDeliver(swarmSecret, "zone_" .. computerId)
    local signedDeliver = Crypto.wrapWith(deliver, displayCode)

    print("[ZONE] Verifying signature with display code...")
    local unwrapped, err = Crypto.unwrapWith(signedDeliver, displayCode)

    if unwrapped then
        print("[ZONE] Signature verified!")
        print("[ZONE] Secret: " .. tostring(unwrapped.data.secret):sub(1, 20) .. "...")
        print("[ZONE] ZoneId: " .. tostring(unwrapped.data.zoneId))

        print("")
        print("[ZONE] Creating PAIR_COMPLETE...")
        local complete = Protocol.createPairComplete("Test Zone")
        print("[ZONE] Type: " .. tostring(complete.type))

        print("")
        print("ZONE TEST PASSED")
    else
        print("[ZONE] ERROR: " .. tostring(err))
        print("ZONE TEST FAILED")
    end

elseif ROLE == "pocket" then
    -- Pocket computer: simulate receiving PAIR_READY and sending PAIR_DELIVER
    print("[POCKET] Generating swarm secret...")
    local swarmSecret = Crypto.generateSecret()
    print("[POCKET] Secret: " .. swarmSecret:sub(1, 20) .. "...")

    print("")
    print("[POCKET] Simulating zone discovery...")
    local zoneId = 42
    local zoneName = "Remote Zone"

    print("[POCKET] Found zone: " .. zoneName .. " (ID: " .. zoneId .. ")")

    print("")
    print("[POCKET] Creating PAIR_DELIVER...")
    local deliver = Protocol.createPairDeliver(swarmSecret, "zone_" .. zoneId)
    print("[POCKET] Type: " .. tostring(deliver.type))
    print("[POCKET] Secret in message: " .. tostring(deliver.data.secret):sub(1, 20) .. "...")

    print("")
    print("[POCKET] Signing with display code 'TEST-CODE'...")
    local signed = Crypto.wrapWith(deliver, "TEST-CODE")
    print("[POCKET] Envelope version: " .. tostring(signed.v))
    print("[POCKET] Has signature: " .. tostring(signed.s ~= nil))

    print("")
    print("[POCKET] Verifying own signature...")
    local verified, err = Crypto.unwrapWith(signed, "TEST-CODE")
    if verified then
        print("[POCKET] Self-verification passed!")
        print("POCKET TEST PASSED")
    else
        print("[POCKET] ERROR: " .. tostring(err))
        print("POCKET TEST FAILED")
    end
end

print("")
print("=== Test Complete ===")
os.shutdown()
