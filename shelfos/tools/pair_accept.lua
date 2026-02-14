-- pair_accept.lua
-- Accept pairing from a pocket computer (bootstrap tool)
-- Run with: mpm run shelfos/tools/pair_accept
-- For computers not yet running ShelfOS, or headless nodes
--
-- SECURITY: A pairing code is displayed on screen (never broadcast)
-- The pocket user must enter this code to complete pairing

local Config = mpm('shelfos/core/Config')
local Pairing = mpm('net/Pairing')

-- Display pairing code on a monitor as large as possible
local function displayPairingCodeOnMonitor(mon, code, label)
    local w, h = mon.getSize()

    -- Determine best text scale (larger monitors get larger text)
    local scale = 1
    if w >= 40 and h >= 20 then
        scale = 2
    elseif w >= 60 and h >= 30 then
        scale = 3
    elseif w >= 80 and h >= 40 then
        scale = 4
    end

    mon.setTextScale(scale)
    w, h = mon.getSize()  -- Re-get size after scale change

    mon.setBackgroundColor(colors.blue)
    mon.clear()

    -- Title
    mon.setTextColor(colors.white)
    local title = "PAIRING CODE"
    mon.setCursorPos(math.floor((w - #title) / 2) + 1, 2)
    mon.write(title)

    -- Code (centered, highlighted)
    mon.setBackgroundColor(colors.white)
    mon.setTextColor(colors.black)
    local codeY = math.floor(h / 2)
    local codeX = math.floor((w - #code) / 2) + 1

    -- Draw background box for code
    for y = codeY - 1, codeY + 1 do
        mon.setCursorPos(codeX - 2, y)
        mon.write(string.rep(" ", #code + 4))
    end

    -- Draw code
    mon.setCursorPos(codeX, codeY)
    mon.write(code)

    -- Instructions
    mon.setBackgroundColor(colors.blue)
    mon.setTextColor(colors.yellow)
    local instr = "Enter on pocket"
    mon.setCursorPos(math.floor((w - #instr) / 2) + 1, h - 2)
    mon.write(instr)

    -- Label at bottom
    mon.setTextColor(colors.lightGray)
    local labelText = label:sub(1, w - 2)
    mon.setCursorPos(math.floor((w - #labelText) / 2) + 1, h - 1)
    mon.write(labelText)
end

-- Clear pairing display from all monitors
local function clearPairingDisplays(monitors)
    for _, name in ipairs(monitors) do
        local mon = peripheral.wrap(name)
        if mon then
            mon.setTextScale(1)
            mon.setBackgroundColor(colors.black)
            mon.setTextColor(colors.white)
            mon.clear()
        end
    end
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

    local modemType = modem.isWireless() and "wireless" or "wired"
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
                    displayPairingCodeOnMonitor(mon, code, computerLabel)
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
        onSuccess = function(secret, pairingCode, zoneId)
            clearPairingDisplays(monitorNames)
            print("")
            print("")
            print("=====================================")
            print("   Pairing Successful!")
            print("=====================================")
            print("")
        end,
        onCancel = function(reason)
            clearPairingDisplays(monitorNames)
            print("")
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
