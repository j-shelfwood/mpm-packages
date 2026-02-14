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
local PairingScreen = mpm('shelfos/ui/PairingScreen')
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

        -- Save the auto-generated config (no network secret yet)
        Config.save(self.config)
        print("[ShelfOS] Auto-configured " .. self.discoveredCount .. " monitor(s)")
        print("")
        print("[ShelfOS] Not in swarm yet.")
        print("[ShelfOS] Press L -> Accept from pocket")
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

-- Initialize networking (if modem available and paired with swarm)
function Kernel:initializeNetwork()
    -- Only init if secret is configured (paired with pocket)
    if not self.config.network or not self.config.network.secret then
        print("[ShelfOS] Network: not in swarm")
        print("          Press L -> Accept from pocket to join")
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
        -- Debug: show first 8 chars of secret to verify swarm membership
        local secretPrefix = tostring(self.config.network.secret):sub(1, 8)
        print("[ShelfOS] Secret prefix: " .. secretPrefix)
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
        elseif result == "link_pocket_accept" then
            self:acceptPocketPairing()
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

-- NOTE: createNetwork() was removed - zones cannot create their own secrets
-- Zones must pair with pocket computer to join swarm (pocket-as-queen architecture)
-- See: mpm-packages/docs/SWARM_ARCHITECTURE.md

-- Host a pairing session (blocking - waits for clients)
-- Requires already being in swarm (has secret)
function Kernel:hostPairing()
    local Pairing = mpm('net/Pairing')

    -- Must be in swarm to host pairing
    if not Config.isInSwarm(self.config) then
        print("")
        print("[!] Not in swarm yet")
        print("    Press L -> Accept from pocket to join first")
        EventUtils.sleep(2)
        return
    end

    -- Ensure pairing code exists
    if not self.config.network.pairingCode then
        self.config.network.pairingCode = Pairing.generateCode()
        Config.save(self.config)
    end

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
    print("On other computers or pocket:")
    print("  Enter this code to join swarm")
    print("")
    print("Press [Q] to stop hosting")
    print("")

    -- Use Pairing module
    local callbacks = {
        onJoin = function(computerId)
            print("[+] Computer #" .. computerId .. " joined!")
        end,
        onCancel = function()
            -- Silent
        end
    }

    local clientsJoined = Pairing.hostSession(
        self.config.network.secret,
        self.config.network.pairingCode,
        self.config.zone.id,
        self.config.zone.name,
        callbacks
    )

    print("")
    print("[*] Pairing session ended")
    print("    " .. clientsJoined .. " computer(s) joined")
    EventUtils.sleep(2)
end

-- Join an existing network using pairing code
function Kernel:joinNetwork(code)
    local Pairing = mpm('net/Pairing')

    -- Close existing channel to avoid conflicts
    if self.channel then
        rednet.unhost("shelfos")
        self.channel:close()
        self.channel = nil
    end

    print("")
    print("[*] Searching for swarm host...")

    local callbacks = {
        onSuccess = function(response)
            print("[*] Joined swarm!")
            print("    Zone: " .. (response.zoneName or "Unknown"))
        end,
        onFail = function(err)
            print("[!] Failed: " .. err)
        end
    }

    local success, secret, pairingCode, zoneId, zoneName = Pairing.joinWithCode(code, callbacks)

    if success then
        -- Save credentials
        Config.setNetworkSecret(self.config, secret)
        if pairingCode then
            self.config.network.pairingCode = pairingCode
        end
        if zoneId then
            self.config.zone.id = zoneId
        end
        Config.save(self.config)

        print("")
        print("[*] Restart ShelfOS to connect")
        EventUtils.sleep(3)
    else
        EventUtils.sleep(2)
    end
end

-- Accept pairing from a pocket computer
-- This is how zones join the swarm - pocket delivers the secret
-- SECURITY: A code is displayed on screen (never broadcast)
-- The pocket user must enter this code to complete pairing
function Kernel:acceptPocketPairing()
    local Pairing = mpm('net/Pairing')

    local modem = peripheral.find("modem")
    if not modem then
        print("")
        print("[!] No modem found")
        EventUtils.sleep(2)
        return
    end

    local modemType = modem.isWireless() and "wireless" or "wired"
    local computerLabel = os.getComputerLabel() or ("Computer #" .. os.getComputerID())

    -- Find all connected monitors
    local monitorNames = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name, "monitor") then
            table.insert(monitorNames, name)
        end
    end

    -- Close existing channel temporarily
    if self.channel then
        rednet.unhost("shelfos")
        self.channel:close()
        self.channel = nil
    end

    -- PAUSE all monitor rendering so pairing code stays visible
    for _, monitor in ipairs(self.monitors) do
        monitor:setPairingMode(true)
    end

    -- Use Pairing module with callbacks
    local displayCode = nil

    -- Reference to self for cleanup in callbacks
    local kernelRef = self

    local callbacks = {
        onDisplayCode = function(code)
            displayCode = code

            -- Display code on ALL monitors (large as possible)
            for _, name in ipairs(monitorNames) do
                local mon = peripheral.wrap(name)
                if mon then
                    PairingScreen.drawCode(mon, code, computerLabel)
                end
            end

            -- Also draw on terminal
            print("")
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
            if #monitorNames > 0 then
                print("Code shown on " .. #monitorNames .. " monitor(s)")
            end
            print("")
            print("On your pocket computer:")
            print("  1. Select 'Add Computer'")
            print("  2. Select this computer")
            print("  3. Enter the code shown")
            print("")
            print("Press [Q] to cancel")
        end,
        onStatus = function(msg)
            -- Update status line (redraw bottom area)
            local _, h = term.getSize()
            term.setCursorPos(1, h - 1)
            term.clearLine()
            term.write("[*] " .. msg)
        end,
        onSuccess = function(secret, pairingCode, zoneId)
            -- RESUME monitor rendering
            for _, monitor in ipairs(kernelRef.monitors) do
                monitor:setPairingMode(false)
            end

            -- Clear monitor displays
            PairingScreen.clearAll(monitorNames)

            print("")
            print("")
            print("[*] Pairing successful!")
            print("[*] Initializing network...")
        end,
        onCancel = function(reason)
            -- RESUME monitor rendering
            for _, monitor in ipairs(kernelRef.monitors) do
                monitor:setPairingMode(false)
            end

            -- Clear monitor displays
            PairingScreen.clearAll(monitorNames)

            print("")
            print("")
            print("[*] " .. (reason or "Cancelled"))
        end
    }

    local success, secret, pairingCode, zoneId = Pairing.acceptFromPocket(callbacks)

    if success then
        -- Save credentials
        Config.setNetworkSecret(self.config, secret)
        if pairingCode then
            self.config.network.pairingCode = pairingCode
        end
        if zoneId then
            self.config.zone = self.config.zone or {}
            self.config.zone.id = zoneId
        end
        Config.save(self.config)

        -- Initialize network immediately (no restart required)
        self:initializeNetwork()
        print("[*] Connected to swarm!")
    end

    EventUtils.sleep(2)
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
