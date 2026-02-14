-- headless.lua
-- Peripheral host mode for ShelfOS
-- Runs on computers without monitors, shares peripherals over network

local Config = mpm('shelfos/core/Config')
local Paths = mpm('shelfos/core/Paths')
local Channel = mpm('net/Channel')
local PeripheralHost = mpm('net/PeripheralHost')
local Pairing = mpm('net/Pairing')
local Crypto = mpm('net/Crypto')
local PairingScreen = mpm('shelfos/ui/PairingScreen')

local headless = {}

-- Draw status to terminal
local function drawStatus(host, channel, config)
    term.clear()
    term.setCursorPos(1, 1)

    print("=====================================")
    print("  ShelfOS - Peripheral Host Mode")
    print("=====================================")
    print("")
    print("Zone: " .. (config.zone.name or "Unknown"))
    print("Computer ID: " .. os.getComputerID())
    print("")

    -- Network status
    if channel and channel:isOpen() then
        print("Network: Connected")
    else
        print("Network: Disconnected")
    end
    print("")

    -- Peripheral list
    print("Shared Peripherals:")
    print("-------------------")

    local peripherals = host:getPeripheralList()
    if #peripherals == 0 then
        print("  (none)")
    else
        for _, p in ipairs(peripherals) do
            print("  [" .. p.type .. "] " .. p.name)
        end
    end

    print("")
    print("-------------------")
    print("[Q] Quit  [R] Rescan  [X] Reset")
end

-- Accept pairing from pocket computer
-- @param config Current configuration
-- @return success, secret, zoneId
function headless.acceptPairing(config)
    local modem = peripheral.find("modem")
    if not modem then
        print("[!] No modem found")
        sleep(2)
        return false, nil, nil
    end

    local modemType = modem.isWireless() and "wireless" or "wired"
    local computerLabel = os.getComputerLabel() or ("Computer #" .. os.getComputerID())

    local displayCode = nil

    local callbacks = {
        onDisplayCode = function(code)
            displayCode = code
            term.clear()
            term.setCursorPos(1, 1)
            print("=====================================")
            print("   Waiting for Pocket Pairing")
            print("=====================================")
            print("")
            print("  Computer: " .. computerLabel)
            print("  Modem: " .. modemType)
            print("")
            print("  +-----------------------+")
            print("  |  PAIRING CODE:        |")
            print("  |                       |")
            print("  |      " .. code .. "      |")
            print("  |                       |")
            print("  +-----------------------+")
            print("")
            print("On your pocket computer:")
            print("  1. Select 'Add Computer'")
            print("  2. Select this computer")
            print("  3. Enter the code shown")
            print("")
            print("Press [Q] to cancel")
        end,
        onStatus = function(msg)
            local _, h = term.getSize()
            term.setCursorPos(1, h)
            term.clearLine()
            term.write("[*] " .. msg)
        end,
        onSuccess = function(secret, zoneId)
            print("")
            print("[*] Pairing successful!")
        end,
        onCancel = function(reason)
            print("")
            print("[*] " .. (reason or "Cancelled"))
        end
    }

    return Pairing.acceptFromPocket(callbacks)
end

-- Run headless mode
function headless.run()
    print("[ShelfOS] Starting in headless mode...")

    -- Clear any stale crypto state from previous session FIRST
    -- _G persists across program restarts in CC:Tweaked
    Crypto.clearSecret()

    -- Load or create config
    local config = Config.load()
    if not config then
        config = Config.create(
            "zone_" .. os.getComputerID() .. "_" .. os.epoch("utc"),
            os.getComputerLabel() or ("Peripheral Node " .. os.getComputerID())
        )
        Config.save(config)
        print("[ShelfOS] Created new configuration")
    end

    -- Check if paired with swarm
    if not config.network or not config.network.secret then
        print("")
        print("[ShelfOS] Not in swarm yet")
        print("")
        print("[L] Accept pairing from pocket")
        print("[Q] Quit")
        print("")

        -- Wait for pairing or quit
        while true do
            local event, key = os.pullEvent("key")
            if key == keys.q then
                return
            elseif key == keys.l then
                -- Run pairing flow
                local success, secret, zoneId = headless.acceptPairing(config)
                if success then
                    -- Save credentials
                    Config.setNetworkSecret(config, secret)
                    if zoneId then
                        config.zone = config.zone or {}
                        config.zone.id = zoneId
                    end
                    Config.save(config)

                    print("")
                    print("[*] Paired successfully!")
                    print("[*] Restarting...")
                    sleep(2)
                    os.reboot()
                else
                    -- Redraw unpaired screen
                    term.clear()
                    term.setCursorPos(1, 1)
                    print("[ShelfOS] Not in swarm yet")
                    print("")
                    print("[L] Accept pairing from pocket")
                    print("[Q] Quit")
                    print("")
                end
            end
        end
    end

    -- Initialize crypto with secret
    Crypto.setSecret(config.network.secret)

    -- Open network channel
    local channel = Channel.new()
    local ok, modemType = channel:open(true)  -- Prefer ender modem

    if not ok then
        print("[!] No modem found")
        print("    Attach a wireless or ender modem")
        print("")
        print("Press any key to exit...")
        os.pullEvent("key")
        return
    end

    print("[ShelfOS] Network: " .. modemType .. " modem")

    -- Create peripheral host
    local host = PeripheralHost.new(channel, config.zone.id, config.zone.name)
    local count = host:start()

    print("[ShelfOS] Sharing " .. count .. " peripheral(s)")

    -- Draw initial status
    drawStatus(host, channel, config)

    -- Event loop
    local running = true
    local lastAnnounce = os.epoch("utc")
    local announceInterval = 10000  -- 10 seconds

    while running do
        -- Poll network with short timeout
        local timer = os.startTimer(0.5)
        local event, p1 = os.pullEvent()

        if event == "timer" and p1 == timer then
            -- Check if should announce
            if os.epoch("utc") - lastAnnounce > announceInterval then
                host:announce()
                lastAnnounce = os.epoch("utc")
            end

            -- Poll for network messages
            channel:poll(0)

        elseif event == "key" then
            local key = p1
            if key == keys.q then
                running = false
            elseif key == keys.r then
                -- Rescan peripherals
                local newCount = host:rescan()
                drawStatus(host, channel, config)
                print("")
                print("Rescanned: " .. newCount .. " peripheral(s)")
            elseif key == keys.x then
                -- Factory reset
                channel:close()
                Crypto.clearSecret()
                Paths.deleteZoneFiles()

                term.clear()
                term.setCursorPos(1, 1)
                print("=====================================")
                print("   FACTORY RESET")
                print("=====================================")
                print("")
                print("Configuration deleted.")
                print("Rebooting in 2 seconds...")
                sleep(2)
                os.reboot()
            end

        elseif event == "peripheral" then
            -- New peripheral attached
            host:rescan()
            drawStatus(host, channel, config)

        elseif event == "peripheral_detach" then
            -- Peripheral removed
            host:rescan()
            drawStatus(host, channel, config)

        elseif event == "rednet_message" then
            -- Handle via channel poll
            channel:poll(0)
        end
    end

    -- Cleanup
    channel:close()

    term.clear()
    term.setCursorPos(1, 1)
    print("[ShelfOS] Peripheral host stopped")
end

return headless
