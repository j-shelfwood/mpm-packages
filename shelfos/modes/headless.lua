-- headless.lua
-- Peripheral host mode for ShelfOS
-- Runs on computers without monitors, shares peripherals over network

local Config = mpm('shelfos/core/Config')
local Paths = mpm('shelfos/core/Paths')
local Channel = mpm('net/Channel')
local PeripheralHost = mpm('net/PeripheralHost')
local Pairing = mpm('net/Pairing')
local Crypto = mpm('net/Crypto')
local ModemUtils = mpm('utils/ModemUtils')
local TermUI = mpm('ui/TermUI')
local KernelNetwork = mpm('shelfos/core/KernelNetwork')
local DashboardUtils = mpm('shelfos/core/DashboardUtils')

local headless = {}

local function newDashboardState()
    return {
        startedAt = os.epoch("utc"),
        lastActivity = {},
        stats = {
            announce = 0,
            discover = 0,
            call = 0,
            call_error = 0,
            rescan = 0,
            attach = 0,
            detach = 0,
            rx = 0,
            reboot = 0
        },
        rate = {
            msgPerSec = 0
        },
        prevRxCount = 0,
        lastRateSampleAt = os.epoch("utc"),
        waitMsSamples = {},
        handlerMsSamples = {},
        callDurationSamples = {},
        message = "Waiting for activity...",
        messageColor = colors.lightGray,
        messageAt = os.epoch("utc"),
        redrawPending = true
    }
end

local function setMessage(state, message, color)
    state.message = message or state.message
    state.messageColor = color or colors.lightGray
    state.messageAt = os.epoch("utc")
    state.redrawPending = true
end

local function markActivity(state, key, message, color)
    local now = os.epoch("utc")
    state.lastActivity[key] = now
    if state.stats[key] ~= nil then
        state.stats[key] = state.stats[key] + 1
    end
    setMessage(state, message, color)
end

local function recordNetworkDrain(state, drained)
    if (drained or 0) > 0 then
        state.stats.rx = state.stats.rx + drained
        state.lastActivity.rx = os.epoch("utc")
        state.redrawPending = true
    end
end

local function updateRates(state)
    local now = os.epoch("utc")
    local elapsed = now - state.lastRateSampleAt
    if elapsed < 1000 then return end

    local rxDelta = state.stats.rx - state.prevRxCount
    state.rate.msgPerSec = (rxDelta * 1000) / elapsed
    state.prevRxCount = state.stats.rx
    state.lastRateSampleAt = now
    state.redrawPending = true
end

local function drawDashboard(host, channel, config, modemType, state)
    TermUI.clear()
    TermUI.drawTitleBar("ShelfOS Headless Dashboard")

    local w, h = TermUI.getSize()
    local now = os.epoch("utc")
    local rightCol = math.max(2, math.floor(w / 2))

    local y = 3
    TermUI.drawMetric(2, y, "Computer", config.computer.name or "Unknown", colors.white)
    TermUI.drawMetric(rightCol, y, "Uptime", DashboardUtils.formatUptime(now - state.startedAt), colors.white)
    y = y + 1

    TermUI.drawMetric(2, y, "Computer ID", os.getComputerID(), colors.lightGray)
    TermUI.drawMetric(rightCol, y, "Modem", modemType or "unknown", colors.lightGray)
    y = y + 1

    local netConnected = channel and channel:isOpen()
    local netLabel = netConnected and "Connected" or "Disconnected"
    local netColor = netConnected and colors.lime or colors.orange
    TermUI.drawMetric(2, y, "Network", netLabel, netColor)
    TermUI.drawMetric(rightCol, y, "Messages/s", string.format("%.1f", state.rate.msgPerSec), colors.cyan)
    y = y + 2

    TermUI.drawSeparator(y, colors.gray)
    y = y + 1
    TermUI.drawText(2, y, "Activity Lights", colors.lightGray)
    y = y + 1

    local col2 = math.max(2, math.floor(w / 3) + 1)
    local col3 = math.max(col2 + 1, math.floor((w * 2) / 3) + 1)

    TermUI.drawActivityLight(2, y, "DISCOVER", state.lastActivity.discover, state.stats.discover, { activeColor = colors.yellow })
    TermUI.drawActivityLight(col2, y, "CALL", state.lastActivity.call, state.stats.call, { activeColor = colors.lime })
    TermUI.drawActivityLight(col3, y, "ANNOUNCE", state.lastActivity.announce, state.stats.announce, { activeColor = colors.cyan })
    y = y + 1

    TermUI.drawActivityLight(2, y, "RX", state.lastActivity.rx, state.stats.rx, { activeColor = colors.lightBlue })
    TermUI.drawActivityLight(col2, y, "RESCAN", state.lastActivity.rescan, state.stats.rescan, { activeColor = colors.orange })
    TermUI.drawActivityLight(col3, y, "ERROR", state.lastActivity.call_error, state.stats.call_error, { activeColor = colors.red })
    y = y + 2

    TermUI.drawSeparator(y, colors.gray)
    y = y + 1
    TermUI.drawText(2, y, "Performance", colors.lightGray)
    y = y + 1

    local avgWaitMs = DashboardUtils.average(state.waitMsSamples)
    local peakWaitMs = DashboardUtils.maxValue(state.waitMsSamples)
    local avgHandlerMs = DashboardUtils.average(state.handlerMsSamples)
    local peakHandlerMs = DashboardUtils.maxValue(state.handlerMsSamples)
    local avgCallMs = DashboardUtils.average(state.callDurationSamples)

    local loopColor = colors.lime
    if avgHandlerMs > 120 then
        loopColor = colors.red
    elseif avgHandlerMs > 60 then
        loopColor = colors.orange
    end

    TermUI.drawMetric(2, y, "Wait avg/peak", string.format("%.0f/%.0f ms", avgWaitMs, peakWaitMs), colors.lightGray)
    TermUI.drawMetric(rightCol, y, "Call avg", string.format("%.0f ms", avgCallMs), colors.white)
    y = y + 1
    TermUI.drawMetric(2, y, "Handler avg/peak", string.format("%.0f/%.0f ms", avgHandlerMs, peakHandlerMs), loopColor)
    y = y + 1

    TermUI.drawMetric(2, y, "Attach/Detach", state.stats.attach .. "/" .. state.stats.detach, colors.white)
    TermUI.drawMetric(rightCol, y, "Reboots", state.stats.reboot, colors.lightGray)
    y = y + 1

    local loopLoad = math.min(100, math.floor((avgHandlerMs / 200) * 100))
    TermUI.drawProgress(y, "Loop Load", loopLoad, { fillColor = loopColor, emptyColor = colors.gray, indent = 2 })
    y = y + 2

    TermUI.drawSeparator(y, colors.gray)
    y = y + 1
    TermUI.drawText(2, y, "Shared Peripherals", colors.lightGray)
    y = y + 1

    local peripherals = host:getPeripheralList()
    if #peripherals == 0 then
        TermUI.drawText(4, y, "(none)", colors.gray)
        y = y + 1
    else
        for _, p in ipairs(peripherals) do
            if y >= h - 2 then break end
            local rowText = "[" .. p.type .. "] " .. p.name
            TermUI.drawText(4, y, DashboardUtils.truncateText(rowText, math.max(1, w - 5)), colors.white)
            y = y + 1
        end
    end

    local statusY = h - 1
    TermUI.clearLine(statusY)
    local statusColor = state.messageColor
    if now - state.messageAt > 4000 then
        statusColor = colors.gray
    end
    TermUI.drawText(2, statusY, DashboardUtils.truncateText(state.message, math.max(1, w - 2)), statusColor)

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

    local callbacks = {
        onDisplayCode = function(code)
            TermUI.clear()
            TermUI.drawTitleBar("Pairing")

            local y = 3
            TermUI.drawInfoLine(y, "Computer", computerLabel, colors.white)
            y = y + 1
            TermUI.drawInfoLine(y, "Modem", modemType, colors.lime)
            y = y + 2

            TermUI.drawCentered(y, "PAIRING CODE", colors.yellow)
            local w = TermUI.getSize()
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
    local hasModem = ModemUtils.hasAny()
    if not hasMonitor and not hasModem then
        TermUI.clear()
        TermUI.drawTitleBar("Headless Mode")
        local y = 4
        TermUI.drawText(2, y, "No monitor or modem detected.", colors.orange)
        y = y + 2
        TermUI.drawWrapped(
            y,
            "Headless mode requires a modem to share peripherals, or a monitor to display network data.",
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
            local _, key = os.pullEvent("key")
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

    local channel, modemType = Channel.openWithSecret(config.network.secret, true)
    if not channel then
        TermUI.clear()
        TermUI.drawTitleBar("Headless Mode")
        TermUI.drawText(2, 4, "No modem found", colors.red)
        TermUI.drawWrapped(6, "Attach a wireless or ender modem to continue.", colors.lightGray, 2, 2)
        TermUI.drawStatusBar("Press any key to exit...")
        os.pullEvent("key")
        return
    end

    -- Create peripheral host
    KernelNetwork.hostService(config.computer.id)
    local host = PeripheralHost.new(channel, config.computer.id, config.computer.name)
    local state = newDashboardState()

    host:setActivityListener(function(activity, data)
        if activity == "discover" then
            markActivity(
                state,
                "discover",
                "Discovery request from #" .. tostring(data.senderId or "?"),
                colors.yellow
            )
        elseif activity == "call" then
            markActivity(
                state,
                "call",
                tostring(data.method or "call") .. " on " .. tostring(data.peripheral or "unknown"),
                colors.lime
            )
            DashboardUtils.appendSample(state.callDurationSamples, data.durationMs or 0, 60)
        elseif activity == "call_error" then
            markActivity(
                state,
                "call_error",
                "Call error: " .. tostring(data.error or "unknown"),
                colors.red
            )
            DashboardUtils.appendSample(state.callDurationSamples, data.durationMs or 0, 60)
        elseif activity == "announce" then
            markActivity(
                state,
                "announce",
                "Announced " .. tostring(data.peripheralCount or 0) .. " peripheral(s)",
                colors.cyan
            )
        elseif activity == "rescan" then
            markActivity(
                state,
                "rescan",
                "Rescan " .. tostring(data.oldCount or 0) .. " -> " .. tostring(data.newCount or 0),
                colors.orange
            )
        elseif activity == "start" then
            setMessage(
                state,
                "Host started with " .. tostring(data.peripheralCount or 0) .. " peripheral(s)",
                colors.lightGray
            )
        end
    end)

    local count = host:start()
    setMessage(state, "Sharing " .. count .. " peripheral(s)", colors.lightGray)

    -- Register REBOOT handler
    KernelNetwork.registerRebootHandler(channel, function(senderId, msg)
        markActivity(state, "reboot", "Reboot command from #" .. tostring(senderId), colors.red)
        drawDashboard(host, channel, config, modemType, state)
        sleep(0.5)
        os.reboot()
    end)

    drawDashboard(host, channel, config, modemType, state)

    -- Event loop
    local running = true
    local lastAnnounce = os.epoch("utc")
    local announceInterval = 10000  -- 10 seconds
    local loopTimer = nil

    local function ensureLoopTimer()
        if not loopTimer then
            loopTimer = os.startTimer(0.25)
        end
    end

    ensureLoopTimer()

    while running do
        local waitStart = os.epoch("utc")
        local event, p1 = os.pullEvent()
        local waitDuration = os.epoch("utc") - waitStart
        local handlerStart = os.epoch("utc")

        if event == "timer" and p1 == loopTimer then
            loopTimer = nil
            if os.epoch("utc") - lastAnnounce > announceInterval then
                host:announce()
                lastAnnounce = os.epoch("utc")
            end

            local drained = KernelNetwork.drainChannel(channel, 0, 50)
            recordNetworkDrain(state, drained)
            ensureLoopTimer()

        elseif event == "key" then
            local key = p1
            if key == keys.q then
                running = false
            elseif key == keys.r then
                local newCount = host:rescan()
                setMessage(state, "Rescanned: " .. newCount .. " peripheral(s)", colors.orange)
            elseif key == keys.x then
                KernelNetwork.close(channel)
                channel = nil
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
            markActivity(state, "attach", "Peripheral attached: " .. tostring(p1), colors.lightBlue)
            host:rescan()

        elseif event == "peripheral_detach" then
            markActivity(state, "detach", "Peripheral detached: " .. tostring(p1), colors.orange)
            host:rescan()

        elseif event == "rednet_message" then
            setMessage(state, "Inbound network traffic", colors.lightBlue)
            local drained = KernelNetwork.drainChannel(channel, 0, 50)
            recordNetworkDrain(state, drained)

        elseif event == "term_resize" then
            TermUI.refreshSize()
            state.redrawPending = true
            ensureLoopTimer()
        end

        local handlerDuration = os.epoch("utc") - handlerStart
        DashboardUtils.appendSample(state.waitMsSamples, waitDuration, 80)
        DashboardUtils.appendSample(state.handlerMsSamples, handlerDuration, 80)
        updateRates(state)

        if state.redrawPending then
            drawDashboard(host, channel, config, modemType, state)
            state.redrawPending = false
        end
    end

    -- Cleanup
    KernelNetwork.close(channel)

    TermUI.clear()
    TermUI.drawTitleBar("Headless Mode")
    TermUI.drawCentered(4, "Peripheral host stopped", colors.lightGray)
end

return headless
