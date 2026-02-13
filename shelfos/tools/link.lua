-- link.lua
-- Network linking tool for ShelfOS swarm pairing
-- Handles both hosting (listening for pair requests) and joining networks

local Config = mpm('shelfos/core/Config')
local Crypto = mpm('net/Crypto')

local link = {}

local PROTOCOL = "shelfos_pair"

-- Show current link status
local function showStatus()
    local config = Config.load()

    print("")
    print("[ShelfOS] Network Status")
    print("")

    if not config then
        print("  Not configured. Run 'mpm run shelfos' first.")
        return
    end

    print("  Zone: " .. (config.zone.name or "Unknown"))
    print("  Zone ID: " .. (config.zone.id or "Unknown"))
    print("")

    if config.network and config.network.secret then
        print("  Network: Enabled")
        print("  Pairing Code: " .. (config.network.pairingCode or "Not set"))

        -- Check for modem
        local modem = peripheral.find("modem")
        if modem then
            local modemType = modem.isWireless() and "Wireless/Ender" or "Wired"
            print("  Modem: " .. modemType)
        else
            print("  Modem: Not found (required for network)")
        end
    else
        print("  Network: Not configured")
    end

    print("")
    print("Commands:")
    print("  mpm run shelfos link new     - Host pairing session")
    print("  mpm run shelfos link <CODE>  - Join with pairing code")
end

-- Host a pairing session (blocking - waits for clients)
local function hostPairing()
    local config = Config.load()

    if not config then
        print("[!] Run 'mpm run shelfos' first to configure")
        return
    end

    -- Check for modem
    local modem = peripheral.find("modem")
    if not modem then
        print("[!] No modem found")
        print("    Attach a wireless or ender modem")
        return
    end

    -- Ensure we have a secret and pairing code
    if not config.network.secret then
        config.network.secret = Crypto.generateSecret()
        config.network.enabled = true
    end

    if not config.network.pairingCode then
        config.network.pairingCode = Config.generatePairingCode()
    end

    Config.save(config)

    -- Open modem
    local modemName = peripheral.getName(modem)
    rednet.open(modemName)

    -- Display pairing info
    term.clear()
    term.setCursorPos(1, 1)

    print("=====================================")
    print("    ShelfOS Network Pairing")
    print("=====================================")
    print("")
    print("  PAIRING CODE:")
    print("")
    print("    " .. config.network.pairingCode)
    print("")
    print("=====================================")
    print("")
    print("On other computers, run:")
    print("  mpm run shelfos link " .. config.network.pairingCode)
    print("")
    print("Waiting for computers to connect...")
    print("Press Q to stop hosting")
    print("")

    -- Listen for pairing requests
    local running = true
    local clientsJoined = 0

    while running do
        -- Use parallel to handle both rednet and keyboard
        local timer = os.startTimer(0.5)
        local event, p1, p2, p3 = os.pullEvent()

        if event == "rednet_message" then
            local senderId = p1
            local message = p2
            local msgProtocol = p3

            if msgProtocol == PROTOCOL and type(message) == "table" then
                if message.type == "pair_request" then
                    -- Validate pairing code
                    if message.code == config.network.pairingCode then
                        -- Send success response with secret and swarm pairing code
                        local response = {
                            type = "pair_response",
                            success = true,
                            secret = config.network.secret,
                            pairingCode = config.network.pairingCode,  -- Share swarm code
                            zoneId = config.zone.id,
                            zoneName = config.zone.name
                        }
                        rednet.send(senderId, response, PROTOCOL)

                        clientsJoined = clientsJoined + 1
                        print("[+] Computer #" .. senderId .. " joined! (" .. clientsJoined .. " total)")
                    else
                        -- Invalid code
                        local response = {
                            type = "pair_response",
                            success = false,
                            error = "Invalid pairing code"
                        }
                        rednet.send(senderId, response, PROTOCOL)
                        print("[-] Computer #" .. senderId .. " - invalid code")
                    end
                end
            end

        elseif event == "key" then
            if p1 == keys.q then
                running = false
            end

        elseif event == "timer" and p1 == timer then
            -- Just keep looping
        end
    end

    rednet.close(modemName)

    print("")
    print("[*] Pairing session ended")
    print("    " .. clientsJoined .. " computer(s) joined")

    if clientsJoined > 0 then
        print("")
        print("[*] Restart ShelfOS to connect with paired computers")
    end
end

-- Join an existing network
local function joinNetwork(code)
    if not code or #code < 8 then
        print("[!] Invalid pairing code")
        print("    Get the code from the network host")
        return
    end

    -- Normalize code (remove dashes, uppercase)
    code = code:upper():gsub("-", "")
    -- Re-add dash in correct position for comparison
    if #code == 8 then
        code = code:sub(1, 4) .. "-" .. code:sub(5, 8)
    end

    local config = Config.load()
    if not config then
        print("[!] Run 'mpm run shelfos' first to configure")
        return
    end

    -- Check for modem
    local modem = peripheral.find("modem")
    if not modem then
        print("[!] No modem found")
        print("    Attach a wireless or ender modem")
        return
    end

    print("")
    print("[ShelfOS] Joining Network")
    print("  Code: " .. code)
    print("")

    -- Open modem for discovery
    local modemName = peripheral.getName(modem)
    rednet.open(modemName)

    print("[*] Searching for network host...")

    -- Broadcast discovery request
    rednet.broadcast({ type = "pair_request", code = code }, PROTOCOL)

    -- Wait for response (10 second timeout)
    local senderId, response = rednet.receive(PROTOCOL, 10)

    if not response then
        print("[!] No response from network host")
        print("")
        print("Make sure:")
        print("  1. Host is running: mpm run shelfos link new")
        print("  2. Both computers have ender modems")
        print("  3. Pairing code is correct")
        rednet.close(modemName)
        return
    end

    if type(response) == "table" and response.type == "pair_response" then
        if response.success then
            -- Got the secret!
            config.network.secret = response.secret
            config.network.enabled = true
            config.zone.id = response.zoneId or config.zone.id

            -- Generate our own pairing code for future use
            if not config.network.pairingCode then
                config.network.pairingCode = Config.generatePairingCode()
            end

            Config.save(config)

            print("[*] Successfully joined network!")
            print("  Zone: " .. (response.zoneName or "Unknown"))
            print("")
            print("[*] Restart ShelfOS to connect")
        else
            print("[!] Pairing failed: " .. (response.error or "Unknown error"))
        end
    else
        print("[!] Invalid response from host")
    end

    rednet.close(modemName)
end

-- Regenerate pairing code
local function regenerateCode()
    local config = Config.load()

    if not config then
        print("[!] Run 'mpm run shelfos' first to configure")
        return
    end

    config.network.pairingCode = Config.generatePairingCode()
    Config.save(config)

    print("[*] New pairing code: " .. config.network.pairingCode)
end

-- Main entry point
function link.run(codeOrCommand)
    if not codeOrCommand then
        showStatus()
    elseif codeOrCommand == "new" or codeOrCommand == "host" then
        hostPairing()
    elseif codeOrCommand == "regen" or codeOrCommand == "regenerate" then
        regenerateCode()
    else
        joinNetwork(codeOrCommand)
    end
end

return link
