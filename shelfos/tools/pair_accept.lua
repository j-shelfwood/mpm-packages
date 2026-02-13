-- pair_accept.lua
-- Accept pairing from a pocket computer (bootstrap tool)
-- Run with: mpm run shelfos/tools/pair_accept
-- For computers not yet running ShelfOS, or headless nodes

local Config = mpm('shelfos/core/Config')
local Pairing = mpm('net/Pairing')

-- Main pairing acceptor
local function acceptPairing()
    -- Check for modem
    local modem = peripheral.find("modem")
    if not modem then
        print("[!] No modem found")
        print("    Attach a wireless or ender modem")
        return false, "No modem"
    end

    local modemType = modem.isWireless() and "wireless" or "wired"
    local computerId = os.getComputerID()
    local computerLabel = os.getComputerLabel() or ("Computer #" .. computerId)

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
    print("  2. Select 'Add Computer'")
    print("  3. Select this computer to pair")
    print("")
    print("Press [Q] to cancel")
    print("")

    -- Use Pairing module
    local callbacks = {
        onStatus = function(msg)
            print("[*] " .. msg)
        end,
        onSuccess = function(secret, pairingCode, zoneId)
            print("")
            print("=====================================")
            print("   Pairing Successful!")
            print("=====================================")
            print("")
        end,
        onCancel = function(reason)
            print("")
            print("[*] " .. (reason or "Cancelled"))
        end
    }

    local success, secret, pairingCode, zoneId = Pairing.acceptFromPocket(callbacks)

    if success then
        -- Load or create config
        local config = Config.load()
        if not config then
            config = Config.create(
                "zone_" .. computerId .. "_" .. os.epoch("utc"),
                computerLabel
            )
        end

        -- Save credentials
        Config.setNetworkSecret(config, secret)
        if pairingCode then
            config.network.pairingCode = pairingCode
        end
        if zoneId then
            config.zone = config.zone or {}
            config.zone.id = zoneId
        end

        Config.save(config)

        print("  Secret received from pocket")
        print("  Restart ShelfOS to connect.")
        print("")

        return true, "Paired successfully"
    end

    return false, "Pairing failed"
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
