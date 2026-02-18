-- KernelNetwork.lua
-- Network initialization and event loop for Kernel
-- Extracted from Kernel.lua for maintainability

local KernelNetwork = {}

-- Drain pending channel messages with bounded work per tick.
-- @param channel Channel instance
-- @param blockTimeout Timeout (seconds) for first poll attempt
-- @param maxDrain Maximum messages to process this tick
-- @return drainedCount
function KernelNetwork.drainChannel(channel, blockTimeout, maxDrain)
    if not channel then
        return 0
    end

    local timeout = blockTimeout or 0
    local limit = maxDrain or 50
    local drained = 0

    while drained < limit do
        local handled = channel:poll(drained == 0 and timeout or 0)
        if not handled then break end
        drained = drained + 1
    end

    return drained
end

-- Register reboot message handler for a channel.
-- @param channel Channel instance
-- @param onReboot Function(senderId, msg)
function KernelNetwork.registerRebootHandler(channel, onReboot)
    local Protocol = mpm('net/Protocol')
    channel:on(Protocol.MessageType.REBOOT, onReboot)
end

-- Initialize networking (if modem available and paired with swarm)
-- @param kernel Kernel instance
-- @param config Current config
-- @param identity Identity instance
-- @return channel, discovery, peripheralHost, peripheralClient (or nils)
function KernelNetwork.initialize(kernel, config, identity)
    local Channel = mpm('net/Channel')
    local Crypto = mpm('net/Crypto')
    local RemotePeripheral = mpm('net/RemotePeripheral')

    -- Only init if secret is configured (paired with pocket)
    if not config.network or not config.network.secret then
        -- CRITICAL: Clear any stale secret from previous session
        -- _G persists across program restarts in CC:Tweaked
        Crypto.clearSecret()
        RemotePeripheral.setClient(nil)
        if kernel.dashboard then
            kernel.dashboard:setNetwork("Not in swarm", colors.orange, "n/a", "offline")
            kernel.dashboard:setSharedCount(0)
            kernel.dashboard:setRemoteCount(0)
            kernel.dashboard:setMessage("Press L -> Accept from pocket to join", colors.orange)
        else
            print("[ShelfOS] Network: not in swarm")
            print("          Press L -> Accept from pocket to join")
        end
        return nil, nil, nil, nil
    end

    local channel, modemType = Channel.openWithSecret(config.network.secret, true)
    if not channel then
        RemotePeripheral.setClient(nil)
        if kernel.dashboard then
            kernel.dashboard:setNetwork("No modem found", colors.red, "n/a", "offline")
            kernel.dashboard:setSharedCount(0)
            kernel.dashboard:setRemoteCount(0)
            kernel.dashboard:setMessage("Network unavailable: no modem found", colors.red)
        else
            print("[ShelfOS] Network: no modem found")
        end
        return nil, nil, nil, nil
    end

    -- ModemUtils now returns "ender" for isWireless()=true modems
    if kernel.dashboard then
        kernel.dashboard:setNetwork("Connected", colors.lime, modemType, "connected")
        kernel.dashboard:setMessage("Network online via " .. modemType .. " modem", colors.lime)
    else
        print("[ShelfOS] Network: " .. modemType .. " modem")
    end

    -- Register with native CC:Tweaked service discovery
    -- Note: rednet.host() requires string hostname, identity:getId() may be number
    rednet.host("shelfos", tostring(identity:getId()))

    -- Set up computer discovery (for rich metadata exchange)
    local Discovery = mpm('net/Discovery')
    local discovery = Discovery.new(channel)
    discovery:setIdentity(identity:getId(), identity:getName())
    discovery:start()

    -- Set up peripheral host to share local peripherals
    local PeripheralHost = mpm('net/PeripheralHost')
    local peripheralHost = PeripheralHost.new(channel, identity:getId(), identity:getName())
    if kernel.dashboard then
        peripheralHost:setActivityListener(function(activity, data)
            kernel.dashboard:onHostActivity(activity, data)
        end)
    end
    local hostCount = peripheralHost:start()
    if kernel.dashboard then
        kernel.dashboard:setSharedCount(hostCount)
    elseif hostCount > 0 then
        print("[ShelfOS] Sharing " .. hostCount .. " local peripheral(s)")
    end

    -- Set up peripheral client for remote peripheral access
    local PeripheralClient = mpm('net/PeripheralClient')

    local peripheralClient = PeripheralClient.new(channel)
    peripheralClient:registerHandlers()

    -- Make client available globally via RemotePeripheral
    RemotePeripheral.setClient(peripheralClient)

    -- Register REBOOT handler - reboots this computer on command from pocket
    KernelNetwork.registerRebootHandler(channel, function(senderId, msg)
        if kernel.dashboard then
            kernel.dashboard:markActivity("call_error", "Reboot command received from #" .. senderId, colors.red)
            kernel.dashboard:render(kernel)
        else
            print("[ShelfOS] Reboot command received from #" .. senderId)
        end
        os.reboot()
    end)

    -- Discover remote peripherals (non-blocking, short timeout)
    local count = peripheralClient:discover(2)
    if kernel.dashboard then
        kernel.dashboard:setRemoteCount(count)
        if count > 0 then
            kernel.dashboard:setMessage("Found " .. count .. " remote peripheral(s)", colors.cyan)
        end
    elseif count > 0 then
        print("[ShelfOS] Found " .. count .. " remote peripheral(s)")
    end

    return channel, discovery, peripheralHost, peripheralClient
end

-- Network event loop
-- @param kernel Kernel instance with channel, discovery, peripheralHost, monitors
-- @param runningRef Shared running flag table { value = true/false }
function KernelNetwork.loop(kernel, runningRef)
    local EventUtils = mpm('utils/EventUtils')
    local Yield = mpm('utils/Yield')
    local lastHostAnnounce = 0
    local hostAnnounceInterval = 10000  -- 10 seconds
    local lastPeriphDiscovery = 0
    local periphDiscoveryInterval = 5000   -- Start aggressive (5s)
    local maxDiscoveryInterval = 30000     -- Slow down to 30s once found
    local lastCleanup = 0
    local cleanupInterval = 5000           -- Clean expired requests every 5s

    while runningRef.value do
        if kernel.channel then
            -- First poll blocks briefly, then drain burst without blocking.
            local drained = KernelNetwork.drainChannel(kernel.channel, 0.5, 50)
            if drained > 0 and kernel.dashboard then
                kernel.dashboard:recordNetworkDrain(drained)
            end

            -- Periodic computer announce
            if kernel.discovery and kernel.discovery:shouldAnnounce() then
                local monitorInfo = {}
                for _, m in ipairs(kernel.monitors) do
                    table.insert(monitorInfo, {
                        name = m:getName(),
                        view = m:getViewName()
                    })
                end
                kernel.discovery:announce(monitorInfo)
                if kernel.dashboard then
                    kernel.dashboard:markActivity("announce", "Swarm metadata announce", colors.cyan)
                end
            end

            -- Periodic peripheral host announce
            if kernel.peripheralHost then
                local now = os.epoch("utc")
                if now - lastHostAnnounce > hostAnnounceInterval then
                    kernel.peripheralHost:announce()
                    lastHostAnnounce = now
                end
            end

            -- Periodic re-discovery of remote peripherals
            -- Always re-discover: handles late-joining hosts, host reboots,
            -- and newly-shared peripherals
            if kernel.peripheralClient then
                local now = os.epoch("utc")
                if now - lastPeriphDiscovery > periphDiscoveryInterval then
                    kernel.peripheralClient:discoverAsync()
                    lastPeriphDiscovery = now
                    if kernel.dashboard then
                        kernel.dashboard:markActivity("discover", "Remote peripheral discovery", colors.yellow)
                    end

                    -- Back off once we have peripherals
                    if kernel.peripheralClient:getCount() > 0 then
                        periphDiscoveryInterval = maxDiscoveryInterval
                    end
                end

                -- Clean up expired async requests (prevents memory leaks)
                if now - lastCleanup > cleanupInterval then
                    kernel.peripheralClient:cleanupExpired()
                    lastCleanup = now
                end
                if kernel.dashboard then
                    kernel.dashboard:setRemoteCount(kernel.peripheralClient:getCount())
                end
            end

            -- CRITICAL: Yield after each iteration to prevent "too long without yielding"
            -- channel:poll() yields via rednet.receive(), but the subsequent announce/broadcast
            -- work can accumulate CPU time across iterations when poll returns quickly
            Yield.yield()
        else
            EventUtils.sleep(1)
        end
    end
end

-- Close network connections
-- @param channel Channel instance
function KernelNetwork.close(channel)
    local RemotePeripheral = mpm('net/RemotePeripheral')
    RemotePeripheral.setClient(nil)
    if channel then
        rednet.unhost("shelfos")
        channel:close()
    end
end

return KernelNetwork
