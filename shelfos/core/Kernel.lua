-- Kernel.lua
-- Main event loop and system orchestration
-- Menu handling uses Controller abstraction for unified terminal/monitor support

local Config = mpm('shelfos/core/Config')
local Monitor = mpm('shelfos/core/Monitor')
local Zone = mpm('shelfos/core/Zone')
local Terminal = mpm('shelfos/core/Terminal')
local Controller = mpm('ui/Controller')
local Menu = mpm('shelfos/input/Menu')
local ViewManager = mpm('views/Manager')
local EventUtils = mpm('utils/EventUtils')
-- Note: TimerDispatch no longer needed - parallel API gives each coroutine its own event queue

local Kernel = {}
Kernel.__index = Kernel

-- Create a new kernel instance
function Kernel.new()
    local self = setmetatable({}, Kernel)
    self.config = nil
    self.zone = nil
    self.monitors = {}
    self.running = false
    self.channel = nil

    return self
end

-- Boot the system
function Kernel:boot()
    -- Initialize terminal windows (log area + menu bar)
    Terminal.init()
    Terminal.clearAll()

    print("[ShelfOS] Booting...")

    -- Load configuration
    self.config = Config.load()

    if not self.config then
        -- Auto-discovery mode: create config automatically
        print("[ShelfOS] First boot - auto-discovering...")
        self.config, self.discoveredCount = Config.autoCreate()

        if self.discoveredCount == 0 then
            print("[ShelfOS] No monitors found.")
            print("[ShelfOS] Connect monitors and restart.")
            return false
        end

        -- Generate pairing code for network linking
        self.config.network.pairingCode = Config.generatePairingCode()

        -- Save the auto-generated config
        Config.save(self.config)
        print("[ShelfOS] Auto-configured " .. self.discoveredCount .. " monitor(s)")
        print("[ShelfOS] Pairing code: " .. self.config.network.pairingCode)
        print("  (view anytime with: mpm run shelfos status)")
        print("")
    end

    -- Initialize zone identity
    self.zone = Zone.new(self.config.zone)
    print("[ShelfOS] Zone: " .. self.zone:getName())

    -- Initialize networking FIRST (so RemotePeripheral is available for view mounting)
    self:initializeNetwork()

    -- Initialize monitors (views can now see remote peripherals)
    self:initializeMonitors()

    if #self.monitors == 0 then
        print("[ShelfOS] No monitors connected.")
        print("[ShelfOS] Check peripheral connections and restart.")
        return false
    end

    -- Draw menu bar
    self:drawMenu()

    return true
end

-- Draw the menu bar
function Kernel:drawMenu()
    Terminal.drawMenu({
        { key = "m", label = "Monitors" },
        { key = "s", label = "Status" },
        { key = "l", label = "Link" },
        { key = "r", label = "Reset" },
        { key = "q", label = "Quit" }
    })
end

-- Initialize all configured monitors
function Kernel:initializeMonitors()
    self.monitors = {}

    -- Create callback for view change persistence (with optional config)
    local function onViewChange(peripheralName, viewName, viewConfig)
        self:persistViewChange(peripheralName, viewName, viewConfig)
    end

    -- Get settings for theme etc.
    local settings = self.config.settings or {}

    for i, monitorConfig in ipairs(self.config.monitors or {}) do
        -- Pass index (0-based) for timer staggering
        local monitor = Monitor.new(monitorConfig, onViewChange, settings, i - 1)

        if monitor:isConnected() then
            table.insert(self.monitors, monitor)
            print("  [+] " .. monitor:getName() .. " -> " .. monitor:getViewName())
        else
            print("  [-] " .. monitorConfig.peripheral .. " (not connected)")
        end
    end
end

-- Persist view change to config (with optional viewConfig)
function Kernel:persistViewChange(peripheralName, viewName, viewConfig)
    if Config.setMonitorView(self.config, peripheralName, viewName, viewConfig) then
        Config.save(self.config)
    end
end

-- Initialize networking (if modem available)
function Kernel:initializeNetwork()
    -- Only init if secret is configured
    if not self.config.network or not self.config.network.secret then
        print("[ShelfOS] Network: disabled (no secret configured)")
        return
    end

    local Channel = mpm('net/Channel')
    local Crypto = mpm('net/Crypto')

    Crypto.setSecret(self.config.network.secret)

    self.channel = Channel.new()
    local ok, modemType = self.channel:open(true)

    if ok then
        print("[ShelfOS] Network: " .. modemType .. " modem")

        -- Register with native CC:Tweaked service discovery
        rednet.host("shelfos", self.zone:getId())

        -- Set up zone discovery (for rich metadata exchange)
        local Discovery = mpm('net/Discovery')
        self.discovery = Discovery.new(self.channel)
        self.discovery:setIdentity(self.zone:getId(), self.zone:getName())
        self.discovery:start()

        -- Set up peripheral host to share local peripherals
        local PeripheralHost = mpm('net/PeripheralHost')
        self.peripheralHost = PeripheralHost.new(self.channel, self.zone:getId(), self.zone:getName())
        local hostCount = self.peripheralHost:start()
        if hostCount > 0 then
            print("[ShelfOS] Sharing " .. hostCount .. " local peripheral(s)")
        end

        -- Set up peripheral client for remote peripheral access
        local PeripheralClient = mpm('net/PeripheralClient')
        local RemotePeripheral = mpm('net/RemotePeripheral')

        self.peripheralClient = PeripheralClient.new(self.channel)
        self.peripheralClient:registerHandlers()

        -- Make client available globally via RemotePeripheral
        RemotePeripheral.setClient(self.peripheralClient)

        -- Discover remote peripherals (non-blocking, short timeout)
        print("[ShelfOS] Discovering remote peripherals...")
        print("[ShelfOS] Crypto ready: " .. tostring(Crypto.hasSecret()))
        local count = self.peripheralClient:discover(2)
        if count > 0 then
            print("[ShelfOS] Found " .. count .. " remote peripheral(s)")
        else
            print("[ShelfOS] No remote peripherals found")
        end
    else
        print("[ShelfOS] Network: no modem found")
        self.channel = nil
    end
end

-- Main run loop
-- ============================================================================
-- PARALLEL ARCHITECTURE (see CC:Tweaked wiki on parallel API)
-- ============================================================================
-- Each function passed to parallel.waitForAny gets its OWN COPY of the event
-- queue. This means:
--   - Each monitor can block (e.g., config menu) without affecting others
--   - Events are delivered to ALL coroutines, each filters for its own
--   - No need for manual event dispatch or requeue mechanisms
-- ============================================================================
function Kernel:run()
    if #self.monitors == 0 then
        -- Boot already handled this message
        return false
    end

    -- Shared running flag (use table so all coroutines see same reference)
    local runningRef = { value = true }

    -- Build task list for parallel execution
    local tasks = {}

    -- Each monitor gets its own coroutine with independent event queue
    for _, monitor in ipairs(self.monitors) do
        table.insert(tasks, function()
            monitor:runLoop(runningRef)
        end)
    end

    -- Main keyboard handler (runs in parallel with monitors)
    table.insert(tasks, function()
        self:keyboardLoop(runningRef)
    end)

    -- Network loop if channel exists
    if self.channel then
        table.insert(tasks, function()
            self:networkLoop(runningRef)
        end)
    end

    -- Run all tasks in parallel - each gets own event queue copy
    parallel.waitForAny(table.unpack(tasks))

    self:shutdown()
end

-- Keyboard event loop - handles terminal menu keys only
-- Runs in parallel with monitor loops (each has own event queue)
function Kernel:keyboardLoop(runningRef)
    while runningRef.value do
        local event, p1 = os.pullEvent()

        if event == "key" then
            -- Handle menu keys - may block for dialogs
            -- Other monitors continue rendering (they have own event queues)
            self:handleMenuKey(p1, runningRef)

        elseif event == "peripheral" or event == "peripheral_detach" then
            -- Rescan shared peripherals when hardware changes
            if self.peripheralHost then
                local count = self.peripheralHost:rescan()
                print("[ShelfOS] Peripheral " .. (event == "peripheral" and "attached" or "detached") .. ": " .. p1)
                print("[ShelfOS] Now sharing " .. count .. " peripheral(s)")
            end
        end
        -- Timer and monitor events are handled by monitor coroutines
    end
end

-- Get monitor by peripheral name
function Kernel:getMonitorByPeripheral(peripheralName)
    for _, monitor in ipairs(self.monitors) do
        if monitor:getPeripheralName() == peripheralName then
            return monitor
        end
    end
    return nil
end

-- Handle menu key press
function Kernel:handleMenuKey(key, runningRef)
    local action = Menu.handleKey(key)

    if action == "quit" then
        runningRef.value = false
        return

    elseif action == "status" then
        Terminal.showDialog(function()
            Menu.showStatus(self.config)
        end)
        Terminal.clearLog()
        self:drawMenu()

    elseif action == "reset" then
        local confirmed = Terminal.showDialog(function()
            return Menu.showReset()
        end)

        if confirmed then
            -- Delete config and quit
            fs.delete(Config.getPath())
            Terminal.clearLog()
            print("[ShelfOS] Configuration deleted.")
            print("[ShelfOS] Restart to auto-configure.")
            EventUtils.sleep(1)
            runningRef.value = false
            return
        else
            Terminal.clearLog()
            self:drawMenu()
        end

    elseif action == "link" then
        local result, code = Terminal.showDialog(function()
            return Menu.showLink(self.config)
        end)

        Terminal.clearLog()

        if result == "link_host" then
            self:hostPairing()
        elseif result == "link_join" and code then
            self:joinNetwork(code)
        elseif result == "link_disconnect" then
            -- Close existing network connection
            if self.channel then
                rednet.unhost("shelfos")
                self.channel:close()
                self.channel = nil
            end
            self.config.network.enabled = false
            self.config.network.secret = nil
            Config.save(self.config)
            print("[ShelfOS] Disconnected from swarm.")
            print("[ShelfOS] Restart to apply changes.")
            EventUtils.sleep(2)
        end

        self:drawMenu()

    elseif action == "monitors" then
        local availableViews = ViewManager.getMountableViews()

        local result, monitorIndex, newView = Terminal.showDialog(function()
            return Menu.showMonitors(self.monitors, availableViews)
        end)

        Terminal.clearLog()

        if result == "change_view" and monitorIndex and newView then
            local monitor = self.monitors[monitorIndex]
            if monitor then
                monitor:loadView(newView)
                self:persistViewChange(monitor:getPeripheralName(), newView)
                print("[ShelfOS] " .. monitor:getName() .. " -> " .. newView)
            end
        end

        self:drawMenu()
    end
end

-- Create a new network
function Kernel:createNetwork()
    local Crypto = mpm('net/Crypto')

    -- Check for modem
    local modem = peripheral.find("modem")
    if not modem then
        print("")
        print("[!] No modem found")
        print("    Attach a wireless or ender modem")
        EventUtils.sleep(2)
        return
    end

    -- Generate secret
    local secret = Crypto.generateSecret()
    Config.setNetworkSecret(self.config, secret)

    -- Generate pairing code if not exists
    if not self.config.network.pairingCode then
        self.config.network.pairingCode = Config.generatePairingCode()
    end

    Config.save(self.config)

    print("")
    print("=================================")
    print("  PAIRING CODE: " .. self.config.network.pairingCode)
    print("=================================")
    print("")
    print("Share this code with other computers.")
    print("Press any key to continue...")
    os.pullEvent("key")
end

-- Host a pairing session (blocking - waits for clients)
function Kernel:hostPairing()
    local Crypto = mpm('net/Crypto')

    -- Check for modem
    local modem = peripheral.find("modem")
    if not modem then
        print("")
        print("[!] No modem found")
        print("    Attach a wireless or ender modem")
        EventUtils.sleep(2)
        return
    end

    -- Ensure we have a secret and pairing code
    if not self.config.network.secret then
        self.config.network.secret = Crypto.generateSecret()
        self.config.network.enabled = true
    end

    if not self.config.network.pairingCode then
        self.config.network.pairingCode = Config.generatePairingCode()
    end

    Config.save(self.config)

    -- Open modem for pairing protocol
    local modemName = peripheral.getName(modem)
    local wasOpen = rednet.isOpen(modemName)
    if not wasOpen then
        rednet.open(modemName)
    end

    local PROTOCOL = "shelfos_pair"

    -- Display pairing info
    print("")
    print("=====================================")
    print("    ShelfOS Swarm Pairing")
    print("=====================================")
    print("")
    print("  PAIRING CODE: " .. self.config.network.pairingCode)
    print("")
    print("=====================================")
    print("")
    print("On other computers, press [L] then [3]")
    print("and enter this code to join the swarm.")
    print("")
    print("Press [Q] to stop hosting")
    print("")

    -- Listen for pairing requests
    local running = true
    local clientsJoined = 0

    while running do
        local timer = os.startTimer(0.5)
        local event, p1, p2, p3 = os.pullEvent()

        if event == "rednet_message" then
            local senderId = p1
            local message = p2
            local msgProtocol = p3

            if msgProtocol == PROTOCOL and type(message) == "table" then
                if message.type == "pair_request" then
                    -- Validate pairing code
                    if message.code == self.config.network.pairingCode then
                        -- Send success response with secret and swarm pairing code
                        local response = {
                            type = "pair_response",
                            success = true,
                            secret = self.config.network.secret,
                            pairingCode = self.config.network.pairingCode,
                            zoneId = self.config.zone.id,
                            zoneName = self.config.zone.name
                        }
                        rednet.send(senderId, response, PROTOCOL)

                        clientsJoined = clientsJoined + 1
                        print("[+] Computer #" .. senderId .. " joined! (" .. clientsJoined .. " total)")
                    else
                        -- Invalid code
                        local response = {
                            type = "pair_response",
                            success = false,
                            error = "Invalid pairing code"
                        }
                        rednet.send(senderId, response, PROTOCOL)
                        print("[-] Computer #" .. senderId .. " - invalid code")
                    end
                end
            end

        elseif event == "key" then
            if p1 == keys.q then
                running = false
            end

        elseif event == "timer" and p1 == timer then
            -- Just keep looping
        end
    end

    -- Only close if we opened it
    if not wasOpen then
        rednet.close(modemName)
    end

    print("")
    print("[*] Pairing session ended")
    print("    " .. clientsJoined .. " computer(s) joined")
    EventUtils.sleep(2)
end

-- Join an existing network
function Kernel:joinNetwork(code)
    -- Check for modem
    local modem = peripheral.find("modem")
    if not modem then
        print("")
        print("[!] No modem found")
        EventUtils.sleep(2)
        return
    end

    -- Close existing channel to avoid conflicts
    local hadChannel = self.channel ~= nil
    if self.channel then
        rednet.unhost("shelfos")
        self.channel:close()
        self.channel = nil
    end

    print("")
    print("[*] Searching for network host...")

    local modemName = peripheral.getName(modem)
    rednet.open(modemName)

    local PROTOCOL = "shelfos_pair"
    rednet.broadcast({ type = "pair_request", code = code }, PROTOCOL)

    local senderId, response = rednet.receive(PROTOCOL, 10)

    if not response then
        print("[!] No response from network host")
        rednet.close(modemName)
        EventUtils.sleep(2)
        return
    end

    if response.type == "pair_response" and response.success then
        -- Save network credentials from swarm
        Config.setNetworkSecret(self.config, response.secret)
        -- Inherit swarm's pairing code (so all swarm members use same code)
        if response.pairingCode then
            self.config.network.pairingCode = response.pairingCode
        end
        self.config.zone.id = response.zoneId or self.config.zone.id
        Config.save(self.config)

        print("[*] Successfully joined swarm!")
        print("    Zone: " .. (response.zoneName or "Unknown"))
        print("")
        print("[*] Restart ShelfOS to connect with swarm")
        EventUtils.sleep(3)
    else
        print("[!] Pairing failed: " .. (response.error or "Unknown error"))
        EventUtils.sleep(2)
    end

    rednet.close(modemName)
end

-- Network event loop
function Kernel:networkLoop(runningRef)
    local lastHostAnnounce = 0
    local hostAnnounceInterval = 10000  -- 10 seconds

    while runningRef.value do
        if self.channel then
            self.channel:poll(0.5)

            -- Periodic zone announce
            if self.discovery and self.discovery:shouldAnnounce() then
                local monitorInfo = {}
                for _, m in ipairs(self.monitors) do
                    table.insert(monitorInfo, {
                        name = m:getName(),
                        view = m:getViewName()
                    })
                end
                self.discovery:announce(monitorInfo)
            end

            -- Periodic peripheral host announce
            if self.peripheralHost then
                local now = os.epoch("utc")
                if now - lastHostAnnounce > hostAnnounceInterval then
                    self.peripheralHost:announce()
                    lastHostAnnounce = now
                end
            end
        else
            EventUtils.sleep(1)
        end
    end
end

-- Shutdown the system
function Kernel:shutdown()
    -- Restore native terminal
    term.redirect(term.native())
    term.clear()
    term.setCursorPos(1, 1)

    print("[ShelfOS] Shutting down...")

    -- Save config
    Config.save(self.config)

    -- Close network
    if self.channel then
        -- Unregister from native service discovery
        rednet.unhost("shelfos")
        self.channel:close()
    end

    -- Clear monitors
    for _, monitor in ipairs(self.monitors) do
        monitor:clear()
    end

    print("[ShelfOS] Goodbye!")
end

-- Get a monitor by peripheral name
function Kernel:getMonitor(peripheralName)
    for _, monitor in ipairs(self.monitors) do
        if monitor.peripheralName == peripheralName then
            return monitor
        end
    end
    return nil
end

-- Reload configuration
function Kernel:reload()
    print("[ShelfOS] Reloading configuration...")
    self.config = Config.load()
    self:initializeMonitors()
end

return Kernel
