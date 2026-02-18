-- pair_accept.lua
-- Accept pairing from a pocket computer (bootstrap tool)
-- Run with: mpm run shelfos/tools/pair_accept
-- For computers not yet running ShelfOS, or headless nodes
--
-- SECURITY: A pairing code is displayed on screen (never broadcast)
-- The pocket user must enter this code to complete pairing

local Config = mpm('shelfos/core/Config')
local Pairing = mpm('net/Pairing')
local PairingScreen = mpm('shelfos/ui/PairingScreen')
local ModemUtils = mpm('utils/ModemUtils')

-- Main pairing acceptor
local function acceptPairing()
    -- Check for modem (prefer wireless/ender for swarm communication)
    local modem, modemName, modemType = ModemUtils.find(true)
    if not modem then
        print("[!] No modem found")
        print("    Attach a wireless or ender modem")
        return false, "No modem"
    end
    local computerId = os.getComputerID()
    local computerLabel = os.getComputerLabel() or ("Computer #" .. computerId)

    -- Find all connected monitors
    local monitorNames = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name, "monitor") then
            table.insert(monitorNames, name)
        end
    end

    -- Use Pairing module with callbacks
    local displayCode = nil

    local callbacks = {
        onDisplayCode = function(code)
            displayCode = code

            -- Display code on ALL monitors (large as possible)
            for _, name in ipairs(monitorNames) do
                local mon = peripheral.wrap(name)
                if mon then
                    PairingScreen.drawCode(mon, code, computerLabel)
                end
            end

            -- Display pairing screen on terminal
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
            print("  +-----------------------+")
            print("  |  PAIRING CODE:        |")
            print("  |                       |")
            print("  |      " .. code .. "      |")
            print("  |                       |")
            print("  +-----------------------+")
            print("")
            if #monitorNames > 0 then
                print("Code shown on " .. #monitorNames .. " monitor(s)")
            end
            print("")
            print("On your pocket computer:")
            print("  1. Open ShelfOS Pocket")
            print("  2. Select 'Add Computer'")
            print("  3. Select this computer")
            print("  4. Enter the code shown")
            print("")
            print("Press [Q] to cancel")
        end,
        onStatus = function(msg)
            -- Update status on last line
            local _, h = term.getSize()
            term.setCursorPos(1, h)
            term.clearLine()
            term.write("[*] " .. msg)
        end,
        onSuccess = function(secret, computerId)
            PairingScreen.clearAll(monitorNames)
            print("")
            print("")
            print("=====================================")
            print("   Pairing Successful!")
            print("=====================================")
            print("")
        end,
        onCancel = function(reason)
            PairingScreen.clearAll(monitorNames)
            print("")
            print("")
            print("[*] " .. (reason or "Cancelled"))
        end
    }

    local success, secret, resultComputerId = Pairing.acceptFromPocket(callbacks)

    if success then
        -- Load or create config
        local config = Config.load()
        if not config then
            config = Config.create(
                "computer_" .. computerId .. "_" .. os.epoch("utc"),
                computerLabel
            )
        end

        -- Save credentials
        Config.setNetworkSecret(config, secret)
        if resultComputerId then
            config.computer = config.computer or {}
            config.computer.id = resultComputerId
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
