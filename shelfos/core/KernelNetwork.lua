-- KernelNetwork.lua
-- Network initialization and event loop for Kernel
-- Extracted from Kernel.lua for maintainability

local KernelNetwork = {}

-- Initialize networking (if modem available and paired with swarm)
-- @param kernel Kernel instance
-- @param config Current config
-- @param zone Zone instance
-- @return channel, discovery, peripheralHost, peripheralClient (or nils)
function KernelNetwork.initialize(kernel, config, zone)
    local Channel = mpm('net/Channel')
    local Crypto = mpm('net/Crypto')

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

    print("[ShelfOS] Network: " .. modemType .. " modem")

    -- Register with native CC:Tweaked service discovery
    rednet.host("shelfos", zone:getId())

    -- Set up zone discovery (for rich metadata exchange)
    local Discovery = mpm('net/Discovery')
    local discovery = Discovery.new(channel)
    discovery:setIdentity(zone:getId(), zone:getName())
    discovery:start()

    -- Set up peripheral host to share local peripherals
    local PeripheralHost = mpm('net/PeripheralHost')
    local peripheralHost = PeripheralHost.new(channel, zone:getId(), zone:getName())
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
    local lastHostAnnounce = 0
    local hostAnnounceInterval = 10000  -- 10 seconds

    while runningRef.value do
        if kernel.channel then
            kernel.channel:poll(0.5)

            -- Periodic zone announce
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
