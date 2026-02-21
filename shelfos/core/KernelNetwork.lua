-- KernelNetwork.lua
-- Network initialization and event loop for Kernel
-- Extracted from Kernel.lua for maintainability

local KernelNetwork = {}
local Yield = mpm('utils/Yield')

-- Register computer in native CC:Tweaked service discovery.
-- @param identityId Computer identity ID (string/number)
function KernelNetwork.hostService(identityId)
    if identityId == nil then
        return
    end
    pcall(rednet.host, "shelfos", tostring(identityId))
end

-- Remove computer from native CC:Tweaked service discovery.
function KernelNetwork.unhostService()
    pcall(rednet.unhost, "shelfos")
end

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
        local handled, received = channel:poll(drained == 0 and timeout or 0)
        if not received then break end
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

    -- Register with native CC:Tweaked service discovery.
    KernelNetwork.hostService(identity:getId())

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
    if not kernel.dashboard and hostCount > 0 then
        print("[ShelfOS] Sharing " .. hostCount .. " local peripheral(s)")
    end

    -- Set up peripheral client for remote peripheral access
    local PeripheralClient = mpm('net/PeripheralClient')
    if not PeripheralClient or type(PeripheralClient.new) ~= "function" then
        RemotePeripheral.setClient(nil)
        if kernel.dashboard then
            kernel.dashboard:setMessage("Remote peripheral client unavailable; host-only mode", colors.orange)
            kernel.dashboard:requestRedraw()
        else
            print("[ShelfOS] Remote peripheral client unavailable; host-only mode")
        end

        return channel, discovery, peripheralHost, nil
    end

    local peripheralClient = PeripheralClient.new(channel)
    peripheralClient:registerHandlers()

    -- Make client available globally via RemotePeripheral
    RemotePeripheral.setClient(peripheralClient)

    -- Register REBOOT handler - reboots this computer on command from pocket
    KernelNetwork.registerRebootHandler(channel, function(senderId, msg)
        if kernel.dashboard then
            kernel.dashboard:markActivity("call_error", "Reboot command received from #" .. senderId, colors.red)
            kernel.dashboard:requestRedraw()
        else
            print("[ShelfOS] Reboot command received from #" .. senderId)
        end
        os.reboot()
    end)

    -- Kick off async discovery. KernelNetwork.loop will poll responses.
    peripheralClient:discoverAsync()
    if kernel.dashboard then
        kernel.dashboard:setMessage("Network initialized; discovering peers...", colors.cyan)
    end

    return channel, discovery, peripheralHost, peripheralClient
end

-- Network event loop
-- @param kernel Kernel instance with channel, discovery, peripheralHost, monitors
-- @param runningRef Shared running flag table { value = true/false }
function KernelNetwork.loop(kernel, runningRef)
    local lastPeriphDiscovery = 0
    local periphDiscoveryInterval = 120000   -- Low-bandwidth discovery sweep
    local lastCleanup = 0
    local cleanupInterval = 5000           -- Clean expired requests every 5s
    local lastDiscoveryCleanup = 0
    local discoveryCleanupInterval = 30000

    while runningRef.value do
        if kernel.channel then
            -- First poll blocks briefly, then drain burst without blocking.
            local drained = KernelNetwork.drainChannel(kernel.channel, 0.5, 50)
            if drained > 0 and kernel.dashboard then
                kernel.dashboard:recordNetworkDrain(drained)
            end

            if kernel.discovery and (os.epoch("utc") - lastDiscoveryCleanup) > discoveryCleanupInterval then
                kernel.discovery:cleanup()
                lastDiscoveryCleanup = os.epoch("utc")
            end

            -- Peripheral host subscription polling
            if kernel.peripheralHost then
                kernel.peripheralHost:pollSubscriptions()
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
                end

                -- Clean up expired async requests (prevents memory leaks)
                if now - lastCleanup > cleanupInterval then
                    kernel.peripheralClient:cleanupExpired()
                    lastCleanup = now
                end
            end

            -- CRITICAL: Yield after each iteration to prevent "too long without yielding"
            -- channel:poll() yields via rednet.receive(), but the subsequent announce/broadcast
            -- work can accumulate CPU time across iterations when poll returns quickly
            Yield.sleep(0)
        else
            Yield.sleep(0.1)
        end
    end
end

-- Close network connections
-- @param channel Channel instance
function KernelNetwork.close(channel)
    local RemotePeripheral = mpm('net/RemotePeripheral')
    RemotePeripheral.setClient(nil)
    KernelNetwork.unhostService()
    if channel then
        channel:close()
    end
end

return KernelNetwork
