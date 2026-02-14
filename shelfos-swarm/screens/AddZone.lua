-- AddZone.lua
-- Zone pairing flow for shelfos-swarm
-- Handles discovery and pairing of zone computers to the swarm
-- Extracted from App.lua for maintainability

local Protocol = mpm('net/Protocol')
local Crypto = mpm('net/Crypto')
local ModemUtils = mpm('utils/ModemUtils')

local AddZone = {}

-- Add a new zone (pairing flow)
-- @param app App instance (needs authority for credential management)
-- @return void
function AddZone.run(app)
    term.clear()
    term.setCursorPos(1, 1)

    print("=====================================")
    print("         Add Zone to Swarm")
    print("=====================================")
    print("")

    -- Open modem with wireless preference (also closes other modems)
    local ok, modemName, modemType = ModemUtils.open(true)
    if not ok then
        print("[!] No modem found")
        print("")
        print("Attach an ender modem to continue.")
        print("Press any key to return...")
        os.pullEvent("key")
        return
    end

    local modemLabel = modemType == "wireless" and "wireless/ender" or "wired"
    print("Modem: " .. modemLabel .. " (" .. modemName .. ")")
    print("")
    print("On the zone computer:")
    print("  1. Run: mpm run shelfos")
    print("  2. Press [L] -> Accept from pocket")
    print("  3. Note the PAIRING CODE shown")
    print("")
    print("Scanning for zones...")
    print("")
    print("[Q] Cancel")

    -- Listen for pairing requests
    local PAIR_PROTOCOL = "shelfos_pair"
    local pendingZones = {}
    local deadline = os.epoch("utc") + 60000  -- 60 second timeout

    while os.epoch("utc") < deadline do
        local timer = os.startTimer(0.5)
        local event, p1, p2, p3 = os.pullEvent()

        if event == "key" and p1 == keys.q then
            return
        elseif event == "rednet_message" and p3 == PAIR_PROTOCOL then
            local senderId = p1
            local msg = p2

            if type(msg) == "table" and msg.type == Protocol.MessageType.PAIR_READY then
                -- New zone requesting pairing
                local zoneId = msg.data.computerId or ("zone_" .. senderId)
                local zoneLabel = msg.data.label or ("Zone " .. senderId)
                -- Note: Zone doesn't have fingerprint yet - we assign one during pairing

                -- Check if already in list
                local found = false
                for _, z in ipairs(pendingZones) do
                    if z.id == zoneId then
                        found = true
                        z.lastSeen = os.epoch("utc")
                        break
                    end
                end

                if not found then
                    table.insert(pendingZones, {
                        id = zoneId,
                        senderId = senderId,
                        label = zoneLabel,
                        lastSeen = os.epoch("utc")
                    })

                    -- Redraw
                    term.clear()
                    term.setCursorPos(1, 1)
                    print("=====================================")
                    print("         Add Zone to Swarm")
                    print("=====================================")
                    print("")
                    print("Found " .. #pendingZones .. " zone(s):")
                    print("")

                    for i, z in ipairs(pendingZones) do
                        print("[" .. i .. "] " .. z.label)
                        print("    Computer ID: " .. z.senderId)
                        print("")
                    end

                    print("Enter number to pair, [Q] to cancel")
                end
            end
        elseif event == "key" then
            -- Number selection
            local num = p1 - keys.one + 1
            if num >= 1 and num <= #pendingZones then
                local zone = pendingZones[num]
                AddZone.completePairing(app, zone)
                return
            end
        end
    end

    print("")
    print("Timeout - no zones found")
    sleep(2)
end

-- Complete pairing with a zone
-- SECURITY: User must enter the code displayed on the zone's screen
-- This code is used to sign the PAIR_DELIVER message
-- @param app App instance (needs authority)
-- @param zone Zone table with id, senderId, label
function AddZone.completePairing(app, zone)
    local PAIR_PROTOCOL = "shelfos_pair"

    term.clear()
    term.setCursorPos(1, 1)

    print("=====================================")
    print("         Pair Zone")
    print("=====================================")
    print("")
    print("Zone: " .. zone.label)
    print("Computer ID: " .. zone.senderId)
    print("")
    print("Enter the CODE shown on the zone's")
    print("screen (format: XXXX-XXXX):")
    print("")
    write("> ")

    local enteredCode = read():upper():gsub("%s", "")

    if not enteredCode or #enteredCode < 4 then
        print("")
        print("[!] Code too short, cancelled")
        sleep(2)
        return
    end

    print("")
    print("[*] Issuing credentials...")

    -- Issue credentials
    local creds, err = app.authority:issueCredentials(zone.id, zone.label)
    if not creds then
        print("[!] Failed: " .. (err or "Unknown error"))
        sleep(2)
        return
    end

    -- Create PAIR_DELIVER message
    local deliverMsg = Protocol.createPairDeliver(creds.swarmSecret, creds.zoneId)

    -- Add full credentials to message
    deliverMsg.data.credentials = creds

    -- Sign with entered code (zone will verify with its display code)
    local signedEnvelope = Crypto.wrapWith(deliverMsg, enteredCode)
    rednet.send(zone.senderId, signedEnvelope, PAIR_PROTOCOL)

    print("[*] Waiting for confirmation...")

    -- Wait for PAIR_COMPLETE
    local deadline = os.epoch("utc") + 5000
    while os.epoch("utc") < deadline do
        local timer = os.startTimer(0.5)
        local event, p1, p2, p3 = os.pullEvent()

        if event == "rednet_message" and p1 == zone.senderId then
            if p3 == PAIR_PROTOCOL and type(p2) == "table" then
                if p2.type == Protocol.MessageType.PAIR_COMPLETE then
                    print("")
                    print("[+] Zone paired successfully!")
                    print("")
                    print("    " .. zone.label .. " joined swarm")
                    print("    Fingerprint: " .. creds.swarmFingerprint)
                    sleep(2)
                    return
                end
            end
        end
    end

    -- No confirmation = wrong code
    print("")
    print("[!] No response - check code was correct")
    print("[*] Zone removed from registry")

    -- Remove from registry since pairing failed
    app.authority:removeZone(zone.id)
    sleep(2)
end

return AddZone
