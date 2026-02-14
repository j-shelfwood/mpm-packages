-- App.lua
-- ShelfOS Swarm - Pocket computer swarm controller
-- The "queen" of the swarm - manages zone registration and revocation

local SwarmAuthority = mpm('shelfos-swarm/core/SwarmAuthority')
local Paths = mpm('shelfos-swarm/core/Paths')
local Channel = mpm('net/Channel')
local Discovery = mpm('net/Discovery')
local Protocol = mpm('net/Protocol')
local Envelope = mpm('crypto/Envelope')
local EventUtils = mpm('utils/EventUtils')

local App = {}
App.__index = App

function App.new()
    local self = setmetatable({}, App)
    self.authority = SwarmAuthority.new()
    self.channel = nil
    self.discovery = nil
    self.running = false
    self.modemType = nil

    return self
end

-- Initialize the app
function App:init()
    term.clear()
    term.setCursorPos(1, 1)

    print("=====================================")
    print("      ShelfOS Swarm Controller")
    print("=====================================")
    print("")

    -- Check for modem
    local modem = peripheral.find("modem")
    if not modem then
        print("[!] No modem found")
        print("    Attach a wireless or ender modem")
        print("")
        print("Press any key to exit...")
        os.pullEvent("key")
        return false
    end

    self.modemType = modem.isWireless() and "wireless" or "wired"
    print("[+] Modem: " .. self.modemType)

    -- Check if swarm exists
    if self.authority:exists() then
        local ok = self.authority:init()
        if ok then
            local info = self.authority:getInfo()
            print("[+] Swarm: " .. info.name)
            print("    Zones: " .. info.zoneCount)
            print("    Fingerprint: " .. info.fingerprint)
        else
            print("[!] Failed to load swarm")
            print("    Data may be corrupted")
            print("")
            print("[R] Reset and create new swarm")
            print("[Q] Quit")

            while true do
                local _, key = os.pullEvent("key")
                if key == keys.r then
                    self.authority:deleteSwarm()
                    print("[*] Swarm deleted, restarting...")
                    sleep(1)
                    os.reboot()
                elseif key == keys.q then
                    return false
                end
            end
        end
    else
        print("[-] No swarm configured")
        print("")
        print("[C] Create new swarm")
        print("[Q] Quit")

        while true do
            local _, key = os.pullEvent("key")
            if key == keys.c then
                return self:createSwarm()
            elseif key == keys.q then
                return false
            end
        end
    end

    -- Initialize networking
    self:initNetwork()

    return true
end

-- Create a new swarm
function App:createSwarm()
    term.clear()
    term.setCursorPos(1, 1)

    print("=====================================")
    print("        Create New Swarm")
    print("=====================================")
    print("")

    print("Enter swarm name:")
    write("> ")
    local name = read()

    if not name or #name == 0 then
        name = "My Swarm"
    end

    print("")
    print("Creating swarm...")

    local ok, swarmId = self.authority:createSwarm(name)
    if not ok then
        print("[!] Failed to create swarm")
        sleep(2)
        return false
    end

    local info = self.authority:getInfo()

    print("")
    print("[+] Swarm created!")
    print("")
    print("    Name: " .. info.name)
    print("    ID: " .. info.id)
    print("    Fingerprint: " .. info.fingerprint)
    print("")
    print("This fingerprint identifies your swarm.")
    print("Zones will display it after pairing.")
    print("")
    print("Press any key to continue...")
    os.pullEvent("key")

    -- Initialize networking
    self:initNetwork()

    return true
end

-- Initialize networking
function App:initNetwork()
    local modem = peripheral.find("modem")
    if not modem then
        return false
    end

    local modemName = peripheral.getName(modem)
    rednet.open(modemName)

    -- Register with service discovery
    local info = self.authority:getInfo()
    if info then
        rednet.host("shelfos_swarm", info.id)
    end

    return true
end

-- Draw main menu
function App:drawMenu()
    term.clear()
    term.setCursorPos(1, 1)

    local info = self.authority:getInfo()

    print("=====================================")
    print("  " .. (info and info.name or "ShelfOS Swarm"))
    print("=====================================")
    print("")

    if info then
        print("Fingerprint: " .. info.fingerprint)
        print("Zones: " .. info.zoneCount .. " active")
    end

    print("")
    print("-------------------")
    print("[A] Add Zone")
    print("[Z] View Zones")
    print("[D] Delete Swarm")
    print("[Q] Quit")
    print("-------------------")
end

-- Run main loop
function App:run()
    self.running = true

    while self.running do
        self:drawMenu()

        local _, key = os.pullEvent("key")

        if key == keys.q then
            self.running = false
        elseif key == keys.a then
            self:addZone()
        elseif key == keys.z then
            self:viewZones()
        elseif key == keys.d then
            self:deleteSwarm()
        end
    end

    self:shutdown()
end

-- Add a new zone (pairing flow)
function App:addZone()
    term.clear()
    term.setCursorPos(1, 1)

    print("=====================================")
    print("         Add Zone to Swarm")
    print("=====================================")
    print("")

    -- Ensure modem is open for receiving
    local modem = peripheral.find("modem")
    if not modem then
        print("[!] No modem found")
        sleep(2)
        return
    end

    local modemName = peripheral.getName(modem)
    if not rednet.isOpen(modemName) then
        rednet.open(modemName)
    end

    local modemType = modem.isWireless() and "wireless/ender" or "wired"
    print("Modem: " .. modemType .. " (" .. modemName .. ")")
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
                self:completeZonePairing(zone)
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
function App:completeZonePairing(zone)
    local Crypto = mpm('net/Crypto')
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
    local creds, err = self.authority:issueCredentials(zone.id, zone.label)
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
    self.authority:removeZone(zone.id)
    sleep(2)
end

-- View all zones
function App:viewZones()
    term.clear()
    term.setCursorPos(1, 1)

    print("=====================================")
    print("           Zone Registry")
    print("=====================================")
    print("")

    local zones = self.authority:getZones()

    if #zones == 0 then
        print("No zones registered.")
        print("")
        print("Use [A] Add Zone to pair computers.")
    else
        for i, zone in ipairs(zones) do
            local status = zone.status == "active" and "+" or "x"
            print("[" .. status .. "] " .. zone.label)
            print("    ID: " .. zone.id)
            print("    Fingerprint: " .. zone.fingerprint)
            print("")
        end
    end

    print("-------------------")
    print("[B] Back")

    while true do
        local _, key = os.pullEvent("key")
        if key == keys.b then
            return
        end
    end
end

-- Delete entire swarm
function App:deleteSwarm()
    term.clear()
    term.setCursorPos(1, 1)

    local info = self.authority:getInfo()

    print("=====================================")
    print("         DELETE SWARM")
    print("=====================================")
    print("")
    print("WARNING: This will delete:")
    print("  - Swarm: " .. (info and info.name or "Unknown"))
    print("  - All " .. (info and info.zoneCount or 0) .. " registered zones")
    print("  - All credentials")
    print("")
    print("Zones will need to re-pair.")
    print("")
    print("[Y] Yes, delete everything")
    print("[N] No, keep swarm")

    while true do
        local _, key = os.pullEvent("key")

        if key == keys.y then
            -- Close network
            rednet.unhost("shelfos_swarm")

            -- Delete swarm
            self.authority:deleteSwarm()
            Paths.deleteAll()

            print("")
            print("[*] Swarm deleted")
            print("Rebooting...")
            sleep(2)
            os.reboot()

        elseif key == keys.n then
            return
        end
    end
end

-- Shutdown
function App:shutdown()
    rednet.unhost("shelfos_swarm")
    term.clear()
    term.setCursorPos(1, 1)
    print("ShelfOS Swarm stopped.")
end

return App
