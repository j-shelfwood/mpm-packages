-- pair_accept.lua
-- Accept pairing from a pocket computer
-- Run with: mpm run shelfos/tools/pair_accept
-- Or triggered from ShelfOS Menu → Link → Accept pairing

local Config = mpm('shelfos/core/Config')
local Protocol = mpm('net/Protocol')

local PAIR_PROTOCOL = "shelfos_pair"
local TOKEN_VALIDITY = 60  -- seconds

-- Generate a random token
local function generateToken()
    local chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    local token = ""
    for i = 1, 16 do
        local idx = math.random(1, #chars)
        token = token .. chars:sub(idx, idx)
    end
    return token
end

-- Main pairing acceptor
local function acceptPairing()
    -- Check for modem
    local modem = peripheral.find("modem")
    if not modem then
        print("[!] No modem found")
        print("    Attach a wireless or ender modem")
        return false, "No modem"
    end

    local modemName = peripheral.getName(modem)
    local modemType = modem.isWireless() and "wireless" or "wired"

    -- Generate one-time token
    local token = generateToken()
    local computerId = os.getComputerID()
    local computerLabel = os.getComputerLabel() or ("Computer #" .. computerId)

    -- Open modem for pairing protocol
    rednet.open(modemName)

    -- Display pairing screen
    term.clear()
    term.setCursorPos(1, 1)

    print("=====================================")
    print("   Waiting for Pocket Pairing")
    print("=====================================")
    print("")
    print("  Computer: " .. computerLabel)
    print("  ID: #" .. computerId)
    print("  Modem: " .. modemType)
    print("")
    print("=====================================")
    print("")
    print("On your pocket computer:")
    print("  1. Open ShelfOS Pocket")
    print("  2. Select 'Add Computer to Swarm'")
    print("  3. Tap this computer to pair")
    print("")
    print("Press [Q] to cancel")
    print("")

    -- Broadcast PAIR_READY
    local msg = Protocol.createPairReady(token, computerLabel, computerId)
    rednet.broadcast(msg, PAIR_PROTOCOL)
    print("[*] Broadcasting pairing request...")

    -- Wait for response or timeout
    local startTime = os.epoch("utc")
    local deadline = startTime + (TOKEN_VALIDITY * 1000)
    local lastBroadcast = startTime

    while os.epoch("utc") < deadline do
        -- Re-broadcast every 3 seconds
        local now = os.epoch("utc")
        if now - lastBroadcast > 3000 then
            rednet.broadcast(msg, PAIR_PROTOCOL)
            lastBroadcast = now
        end

        -- Check for response or key press
        local timer = os.startTimer(0.5)
        local event, p1, p2, p3 = os.pullEvent()

        if event == "rednet_message" then
            local senderId = p1
            local response = p2
            local msgProtocol = p3

            if msgProtocol == PAIR_PROTOCOL and type(response) == "table" then
                if response.type == Protocol.MessageType.PAIR_DELIVER then
                    -- Verify token
                    if response.data and response.data.token == token then
                        -- Token matches! Save the secret
                        local config = Config.load() or Config.create()

                        config.network = config.network or {}
                        config.network.secret = response.data.secret
                        config.network.enabled = true
                        config.network.pairingCode = response.data.pairingCode

                        -- Optionally update zone info
                        if response.data.zoneId then
                            config.zone = config.zone or {}
                            config.zone.id = response.data.zoneId
                        end

                        Config.save(config)

                        -- Send confirmation
                        local complete = Protocol.createPairComplete(computerLabel)
                        rednet.send(senderId, complete, PAIR_PROTOCOL)

                        rednet.close(modemName)

                        print("")
                        print("=====================================")
                        print("   Pairing Successful!")
                        print("=====================================")
                        print("")
                        print("  Joined swarm from pocket #" .. senderId)
                        if response.data.zoneName then
                            print("  Zone: " .. response.data.zoneName)
                        end
                        print("")
                        print("  Restart ShelfOS to connect.")
                        print("")

                        return true, "Paired successfully"
                    else
                        print("[!] Invalid token received - ignoring")
                    end

                elseif response.type == Protocol.MessageType.PAIR_REJECT then
                    rednet.close(modemName)
                    print("")
                    print("[!] Pairing rejected: " .. (response.data and response.data.reason or "Unknown"))
                    return false, "Rejected"
                end
            end

        elseif event == "key" then
            if p1 == keys.q then
                -- User cancelled
                local reject = Protocol.createPairReject("User cancelled")
                rednet.broadcast(reject, PAIR_PROTOCOL)
                rednet.close(modemName)
                print("")
                print("[*] Pairing cancelled")
                return false, "Cancelled"
            end

        elseif event == "timer" and p1 == timer then
            -- Update countdown
            local remaining = math.ceil((deadline - os.epoch("utc")) / 1000)
            term.setCursorPos(1, 18)
            term.clearLine()
            print("Timeout in " .. remaining .. "s...")
        end
    end

    -- Timeout
    rednet.close(modemName)
    print("")
    print("[!] Pairing timed out")
    print("    No pocket computer responded")
    return false, "Timeout"
end

-- Run if executed directly
local success, result = acceptPairing()
if not success then
    print("")
    print("Press any key to exit...")
    os.pullEvent("key")
end

return {
    run = acceptPairing
}
