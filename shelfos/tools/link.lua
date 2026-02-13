-- link.lua
-- Network linking tool for ShelfOS swarm pairing
-- Uses the consolidated Pairing module

local Config = mpm('shelfos/core/Config')
local Pairing = mpm('net/Pairing')

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

    print("  Zone: " .. (config.zone.name or "Unknown"))
    print("  Zone ID: " .. (config.zone.id or "Unknown"))
    print("")

    if Config.isInSwarm(config) then
        print("  Swarm: Connected")
        print("  Pairing Code: " .. (config.network.pairingCode or "Not set"))

        -- Check for modem
        local modem = peripheral.find("modem")
        if modem then
            local modemType = modem.isWireless() and "Wireless/Ender" or "Wired"
            print("  Modem: " .. modemType)
        else
            print("  Modem: Not found")
        end
    else
        print("  Swarm: Not connected")
        print("")
        print("  To join a swarm:")
        print("    1. Run: mpm run shelfos/tools/pair_accept")
        print("    2. Pair from pocket computer")
    end

    print("")
    print("Commands:")
    print("  mpm run shelfos link          - Show status")
    print("  mpm run shelfos link host     - Host pairing (if in swarm)")
    print("  mpm run shelfos link <CODE>   - Join with code (if in swarm)")
end

-- Host a pairing session (requires being in swarm already)
local function hostPairing()
    local config = Config.load()

    if not config then
        print("[!] Run 'mpm run shelfos' first to configure")
        return
    end

    if not Config.isInSwarm(config) then
        print("[!] Not in swarm yet")
        print("    Use pocket computer to join first")
        print("    Or run: mpm run shelfos/tools/pair_accept")
        return
    end

    -- Ensure pairing code exists
    if not config.network.pairingCode then
        config.network.pairingCode = Pairing.generateCode()
        Config.save(config)
    end

    -- Display info
    term.clear()
    term.setCursorPos(1, 1)

    print("=====================================")
    print("    ShelfOS Swarm Pairing")
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
    print("Or use pocket: 'Join Swarm' with this code")
    print("")
    print("Press Q to stop hosting")
    print("")

    -- Use Pairing module to host
    local callbacks = {
        onJoin = function(computerId)
            print("[+] Computer #" .. computerId .. " joined!")
        end,
        onCancel = function()
            print("")
            print("[*] Hosting stopped")
        end
    }

    local clientsJoined = Pairing.hostSession(
        config.network.secret,
        config.network.pairingCode,
        config.zone.id,
        config.zone.name,
        callbacks
    )

    print("")
    print("[*] " .. clientsJoined .. " computer(s) joined")

    if clientsJoined > 0 then
        print("[*] They should restart to connect")
    end
end

-- Join an existing swarm with code (requires being in swarm already)
-- This is for adding THIS computer to another zone's swarm
local function joinWithCode(code)
    if not code or #code < 4 then
        print("[!] Invalid pairing code")
        return
    end

    local config = Config.load()

    if not config then
        print("[!] Run 'mpm run shelfos' first")
        return
    end

    -- Normalize code
    code = code:upper():gsub("[%-%s]", "")

    print("")
    print("[*] Searching for swarm host...")

    local callbacks = {
        onStatus = function(msg)
            print("[*] " .. msg)
        end,
        onSuccess = function(response)
            print("[*] Joined swarm!")
            print("    Zone: " .. (response.zoneName or "Unknown"))
        end,
        onFail = function(err)
            print("[!] Failed: " .. err)
        end
    }

    local success, secret, pairingCode, zoneId, zoneName = Pairing.joinWithCode(code, callbacks)

    if success then
        -- Save credentials
        Config.setNetworkSecret(config, secret)
        if pairingCode then
            config.network.pairingCode = pairingCode
        end
        Config.save(config)

        print("")
        print("[*] Restart ShelfOS to connect")
    end
end

-- Regenerate pairing code
local function regenerateCode()
    local config = Config.load()

    if not config then
        print("[!] Run 'mpm run shelfos' first")
        return
    end

    if not Config.isInSwarm(config) then
        print("[!] Not in swarm - nothing to regenerate")
        return
    end

    config.network.pairingCode = Pairing.generateCode()
    Config.save(config)

    print("[*] New pairing code: " .. config.network.pairingCode)
end

-- Main entry point
function link.run(codeOrCommand)
    if not codeOrCommand then
        showStatus()
    elseif codeOrCommand == "host" or codeOrCommand == "new" then
        hostPairing()
    elseif codeOrCommand == "regen" or codeOrCommand == "regenerate" then
        regenerateCode()
    else
        joinWithCode(codeOrCommand)
    end
end

return link
