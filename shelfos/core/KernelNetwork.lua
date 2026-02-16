-- KernelNetwork.lua
-- Network initialization and event loop for Kernel
-- Extracted from Kernel.lua for maintainability

local KernelNetwork = {}

-- Initialize networking (if modem available and paired with swarm)
-- @param kernel Kernel instance
-- @param config Current config
-- @param identity Identity instance
-- @return channel, discovery, peripheralHost, peripheralClient (or nils)
function KernelNetwork.initialize(kernel, config, identity)
    local Channel = mpm('net/Channel')
    local Crypto = mpm('net/Crypto')
    local Protocol = mpm('net/Protocol')

    -- Only init if secret is configured (paired with pocket)
    if not config.network or not config.network.secret then
        -- CRITICAL: Clear any stale secret from previous session
        -- _G persists across program restarts in CC:Tweaked
        Crypto.clearSecret()
        print("[ShelfOS] Network: not in swarm")
        print("          Press L -> Accept from pocket to join")
        return nil, nil, nil, nil
    end

    Crypto.setSecret(config.network.secret)

    local channel = Channel.new()
    local ok, modemType = channel:open(true)

    if not ok then
        print("[ShelfOS] Network: no modem found")
        return nil, nil, nil, nil
    end

    -- ModemUtils now returns "ender" for isWireless()=true modems
    print("[ShelfOS] Network: " .. modemType .. " modem")

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
    local hostCount = peripheralHost:start()
    if hostCount > 0 then
        print("[ShelfOS] Sharing " .. hostCount .. " local peripheral(s)")
    end

    -- Set up peripheral client for remote peripheral access
    local PeripheralClient = mpm('net/PeripheralClient')
    local RemotePeripheral = mpm('net/RemotePeripheral')

    local peripheralClient = PeripheralClient.new(channel)
    peripheralClient:registerHandlers()

    -- Make client available globally via RemotePeripheral
    RemotePeripheral.setClient(peripheralClient)

    -- Register REBOOT handler - reboots this computer on command from pocket
    channel:on(Protocol.MessageType.REBOOT, function(senderId, msg)
        print("[ShelfOS] Reboot command received from #" .. senderId)
        os.reboot()
    end)

    -- Discover remote peripherals (non-blocking, short timeout)
    local count = peripheralClient:discover(2)
    if count > 0 then
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
            -- Drain ALL pending messages per iteration (up to safety limit)
            -- Single poll() only processes one message, causing response backlog
            -- when multiple monitors make concurrent RPC calls
            local maxDrain = 50
            local drained = 0
            while drained < maxDrain do
                -- First iteration: block up to 0.5s waiting for a message
                -- Subsequent: non-blocking (timeout=0) to drain queued messages
                local handled = kernel.channel:poll(drained == 0 and 0.5 or 0)
                if not handled then break end
                drained = drained + 1
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
    if channel then
        rednet.unhost("shelfos")
        channel:close()
    end
end

return KernelNetwork
