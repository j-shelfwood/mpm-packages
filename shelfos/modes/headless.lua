-- headless.lua
-- Peripheral host mode for ShelfOS
-- Runs on computers without monitors, shares peripherals over network

local Config = mpm('shelfos/core/Config')
local Channel = mpm('net/Channel')
local PeripheralHost = mpm('net/PeripheralHost')
local Crypto = mpm('net/Crypto')

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
    print("Press Q to quit")
    print("Press R to rescan peripherals")
end

-- Run headless mode
function headless.run()
    print("[ShelfOS] Starting in headless mode...")

    -- Load or create config
    local config = Config.load()
    if not config then
        config = Config.create(
            "zone_" .. os.getComputerID() .. "_" .. os.epoch("utc"),
            os.getComputerLabel() or ("Peripheral Node " .. os.getComputerID())
        )
        config.network.enabled = true
        Config.save(config)
        print("[ShelfOS] Created new configuration")
    end

    -- Initialize crypto if secret exists
    if config.network and config.network.secret then
        Crypto.setSecret(config.network.secret)
    end

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
