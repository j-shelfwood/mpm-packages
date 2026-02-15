-- headless.lua
-- Peripheral host mode for ShelfOS
-- Runs on computers without monitors, shares peripherals over network

local Config = mpm('shelfos/core/Config')
local Paths = mpm('shelfos/core/Paths')
local Channel = mpm('net/Channel')
local Protocol = mpm('net/Protocol')
local PeripheralHost = mpm('net/PeripheralHost')
local Pairing = mpm('net/Pairing')
local Crypto = mpm('net/Crypto')
local PairingScreen = mpm('shelfos/ui/PairingScreen')
local ModemUtils = mpm('utils/ModemUtils')
local TermUI = mpm('ui/TermUI')

local headless = {}

-- Draw status to terminal
local function drawStatus(host, channel, config)
    TermUI.clear()
    TermUI.drawTitleBar("ShelfOS Headless")

    local y = 3
    TermUI.drawInfoLine(y, "Computer", config.computer.name or "Unknown", colors.white)
    y = y + 1
    TermUI.drawInfoLine(y, "Computer ID", os.getComputerID(), colors.lightGray)
    y = y + 2

    local netConnected = channel and channel:isOpen()
    local netLabel = netConnected and "Connected" or "Disconnected"
    local netColor = netConnected and colors.lime or colors.orange
    TermUI.drawInfoLine(y, "Network", netLabel, netColor)
    y = y + 2

    TermUI.drawSeparator(y, colors.gray)
    y = y + 1
    TermUI.drawText(2, y, "Shared Peripherals", colors.lightGray)
    y = y + 1

    local peripherals = host:getPeripheralList()
    local _, h = TermUI.getSize()
    if #peripherals == 0 then
        TermUI.drawText(4, y, "(none)", colors.gray)
        y = y + 1
    else
        for _, p in ipairs(peripherals) do
            if y >= h - 1 then break end
            TermUI.drawText(4, y, "[" .. p.type .. "] " .. p.name, colors.white)
            y = y + 1
        end
    end

    TermUI.drawStatusBar({
        { key = "Q", label = "Quit" },
        { key = "R", label = "Rescan" },
        { key = "X", label = "Reset" }
    })
end

-- Accept pairing from pocket computer
-- @param config Current configuration
-- @return success, secret, computerId
function headless.acceptPairing(config)
    -- Pre-validate modem exists (Pairing.acceptFromPocket will open it)
    local modem, modemName, modemType = ModemUtils.find(true)
    if not modem then
        TermUI.clear()
        TermUI.drawTitleBar("Pairing")
        TermUI.drawText(2, 4, "No modem found", colors.red)
        TermUI.drawWrapped(6, "Attach a wireless or ender modem to continue.", colors.lightGray, 2, 2)
        TermUI.drawStatusBar("Press any key to return...")
        os.pullEvent("key")
        return false, nil, nil
    end
    local computerLabel = os.getComputerLabel() or ("Computer #" .. os.getComputerID())

    local displayCode = nil

    local callbacks = {
        onDisplayCode = function(code)
            displayCode = code
            TermUI.clear()
            TermUI.drawTitleBar("Pairing")

            local y = 3
            TermUI.drawInfoLine(y, "Computer", computerLabel, colors.white)
            y = y + 1
            TermUI.drawInfoLine(y, "Modem", modemType, colors.lime)
            y = y + 2

            TermUI.drawCentered(y, "PAIRING CODE", colors.yellow)
            local w, h = TermUI.getSize()
            local codeY = y + 2
            term.setCursorPos(math.floor((w - #code) / 2) + 1, codeY)
            term.setBackgroundColor(colors.white)
            term.setTextColor(colors.black)
            term.write(code)
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)

            y = codeY + 2
            TermUI.drawText(2, y, "On your pocket computer:", colors.lightGray)
            TermUI.drawText(4, y + 1, "1. Select 'Add Computer'", colors.white)
            TermUI.drawText(4, y + 2, "2. Select this computer", colors.white)
            TermUI.drawText(4, y + 3, "3. Enter the code shown", colors.white)
            TermUI.drawStatusBar("Press [Q] to cancel")
        end,
        onStatus = function(msg)
            local _, h = TermUI.getSize()
            TermUI.clearLine(h - 1)
            TermUI.drawText(2, h - 1, "[*] " .. msg, colors.yellow)
        end,
        onSuccess = function(secret, computerId)
            TermUI.drawStatusBar("Pairing successful!")
        end,
        onCancel = function(reason)
            TermUI.drawStatusBar(reason or "Cancelled")
        end
    }

    return Pairing.acceptFromPocket(callbacks)
end

-- Run headless mode
function headless.run()
    TermUI.clear()
    TermUI.drawTitleBar("ShelfOS Headless")
    TermUI.drawText(2, 3, "Starting...", colors.lightGray)

    -- Clear any stale crypto state from previous session FIRST
    -- _G persists across program restarts in CC:Tweaked
    Crypto.clearSecret()

    -- Load or create config
    local config = Config.load()
    if not config then
        config = Config.create(
            "computer_" .. os.getComputerID() .. "_" .. os.epoch("utc"),
            os.getComputerLabel() or ("Peripheral Node " .. os.getComputerID())
        )
        Config.save(config)
        TermUI.drawText(2, 5, "Created new configuration", colors.lightGray)
    end

    local hasMonitor = peripheral.find("monitor") ~= nil
    local hasEnder = ModemUtils.hasEnder()
    if not hasMonitor and not hasEnder then
        TermUI.clear()
        TermUI.drawTitleBar("Headless Mode")
        local y = 4
        TermUI.drawText(2, y, "No monitors or ender modem detected.", colors.orange)
        y = y + 2
        TermUI.drawWrapped(
            y,
            "Headless mode requires an ender modem to share peripherals, or a monitor to display network data.",
            colors.lightGray,
            2,
            3
        )
        TermUI.drawStatusBar("Press any key to exit...")
        os.pullEvent("key")
        return
    end

    -- Check if paired with swarm
    if not config.network or not config.network.secret then
        TermUI.clear()
        TermUI.drawTitleBar("ShelfOS Headless")
        local y = 4
        TermUI.drawText(2, y, "Not in swarm yet", colors.lightGray)
        y = y + 2
        TermUI.drawMenuItem(y, "L", "Accept pairing from pocket")
        y = y + 1
        TermUI.drawMenuItem(y, "Q", "Quit")
        TermUI.drawStatusBar("Select an option")

        -- Wait for pairing or quit
        while true do
            local event, key = os.pullEvent("key")
            if key == keys.q then
                return
            elseif key == keys.l then
                -- Run pairing flow
                local success, secret, computerId = headless.acceptPairing(config)
                if success then
                    -- Save credentials
                    Config.setNetworkSecret(config, secret)
                    if computerId then
                        config.computer = config.computer or {}
                        config.computer.id = computerId
                    end
                    Config.save(config)

                    TermUI.drawStatusBar("Paired successfully. Restarting...")
                    sleep(2)
                    os.reboot()
                else
                    -- Redraw unpaired screen
                    TermUI.clear()
                    TermUI.drawTitleBar("ShelfOS Headless")
                    local redrawY = 4
                    TermUI.drawText(2, redrawY, "Not in swarm yet", colors.lightGray)
                    redrawY = redrawY + 2
                    TermUI.drawMenuItem(redrawY, "L", "Accept pairing from pocket")
                    redrawY = redrawY + 1
                    TermUI.drawMenuItem(redrawY, "Q", "Quit")
                    TermUI.drawStatusBar("Select an option")
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
        TermUI.clear()
        TermUI.drawTitleBar("Headless Mode")
        TermUI.drawText(2, 4, "No modem found", colors.red)
        TermUI.drawWrapped(6, "Attach a wireless or ender modem to continue.", colors.lightGray, 2, 2)
        TermUI.drawStatusBar("Press any key to exit...")
        os.pullEvent("key")
        return
    end

    TermUI.drawText(2, 7, "Network: " .. modemType .. " modem", colors.lightGray)

    -- Create peripheral host
    local host = PeripheralHost.new(channel, config.computer.id, config.computer.name)
    local count = host:start()

    TermUI.drawText(2, 8, "Sharing " .. count .. " peripheral(s)", colors.lightGray)

    -- Register REBOOT handler
    channel:on(Protocol.MessageType.REBOOT, function(senderId, msg)
        TermUI.drawStatusBar("Reboot command received from #" .. senderId)
        os.reboot()
    end)

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
                TermUI.drawStatusBar("Rescanned: " .. newCount .. " peripheral(s)")
            elseif key == keys.x then
                -- Factory reset
                channel:close()
                Crypto.clearSecret()
                Paths.deleteFiles()

                TermUI.clear()
                TermUI.drawTitleBar("FACTORY RESET", colors.red)
                TermUI.drawText(2, 4, "Configuration deleted.", colors.lightGray)
                TermUI.drawText(2, 5, "Rebooting in 2 seconds...", colors.lightGray)
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

    TermUI.clear()
    TermUI.drawTitleBar("Headless Mode")
    TermUI.drawCentered(4, "Peripheral host stopped", colors.lightGray)
end

return headless
