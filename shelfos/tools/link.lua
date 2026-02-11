-- link.lua
-- Network linking tool for ShelfOS swarm pairing

local Config = mpm('shelfos/core/Config')
local Crypto = mpm('net/Crypto')

local link = {}

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

    if config.network and config.network.enabled then
        print("  Status: Linked")
        print("  Zone: " .. config.zone.name)
        print("  Zone ID: " .. config.zone.id)

        -- Check for modem
        local modem = peripheral.find("modem")
        if modem then
            print("  Modem: Connected")
        else
            print("  Modem: Not found (required for network)")
        end
    else
        print("  Status: Standalone (not linked)")
        print("")
        print("  To create a new network:")
        print("    mpm run shelfos link new")
        print("")
        print("  To join existing network:")
        print("    mpm run shelfos link <CODE>")
    end
end

-- Create a new network
local function createNetwork()
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
    print("[ShelfOS] Creating New Network")
    print("")

    -- Generate secret
    local secret = Crypto.generateSecret()
    Config.setNetworkSecret(config, secret)
    Config.save(config)

    -- Generate pairing code
    local pairingCode = Config.generatePairingCode()

    print("Network created successfully!")
    print("")
    print("=================================")
    print("  PAIRING CODE: " .. pairingCode)
    print("=================================")
    print("")
    print("Share this code with other computers")
    print("to add them to your network.")
    print("")
    print("On other computers, run:")
    print("  mpm run shelfos link " .. pairingCode)
    print("")

    -- Store the pairing code temporarily for discovery
    config.network.pairingCode = pairingCode
    Config.save(config)

    print("[*] Network enabled. Restart ShelfOS to activate.")
end

-- Join an existing network
local function joinNetwork(code)
    if not code or #code < 8 then
        print("[!] Invalid pairing code")
        print("    Get the code from the network host")
        return
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
    local PROTOCOL = "shelfos_pair"
    rednet.broadcast({ type = "pair_request", code = code }, PROTOCOL)

    -- Wait for response
    local senderId, response = rednet.receive(PROTOCOL, 10)

    if not response then
        print("[!] No response from network host")
        print("    Make sure the host is running ShelfOS")
        rednet.close(modemName)
        return
    end

    if response.type == "pair_response" and response.success then
        -- Got the secret!
        Config.setNetworkSecret(config, response.secret)
        config.zone.id = response.zoneId or config.zone.id
        Config.save(config)

        print("[*] Successfully joined network!")
        print("  Zone: " .. (response.zoneName or "Unknown"))
        print("")
        print("[*] Restart ShelfOS to activate networking")
    else
        print("[!] Pairing failed: " .. (response.error or "Unknown error"))
    end

    rednet.close(modemName)
end

-- Main entry point
function link.run(codeOrCommand)
    if not codeOrCommand then
        showStatus()
    elseif codeOrCommand == "new" then
        createNetwork()
    else
        joinNetwork(codeOrCommand)
    end
end

return link
