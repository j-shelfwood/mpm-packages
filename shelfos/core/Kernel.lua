-- Kernel.lua
-- Main event loop and system orchestration

local Config = mpm('shelfos/core/Config')
local Monitor = mpm('shelfos/core/Monitor')
local Zone = mpm('shelfos/core/Zone')
local Terminal = mpm('shelfos/core/Terminal')
local Menu = mpm('shelfos/input/Menu')
local ViewManager = mpm('views/Manager')

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

    -- Initialize monitors
    self:initializeMonitors()

    -- Initialize networking (optional)
    self:initializeNetwork()

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

    -- Create callback for view change persistence
    local function onViewChange(peripheralName, viewName)
        self:persistViewChange(peripheralName, viewName)
    end

    for _, monitorConfig in ipairs(self.config.monitors or {}) do
        local monitor = Monitor.new(monitorConfig, onViewChange)

        if monitor:isConnected() then
            table.insert(self.monitors, monitor)
            print("  [+] " .. monitor:getName() .. " -> " .. monitor:getViewName())
        else
            print("  [-] " .. monitorConfig.peripheral .. " (not connected)")
        end
    end
end

-- Persist view change to config
function Kernel:persistViewChange(peripheralName, viewName)
    if Config.setMonitorView(self.config, peripheralName, viewName) then
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

        -- Set up zone discovery
        local Discovery = mpm('net/Discovery')
        self.discovery = Discovery.new(self.channel)
        self.discovery:setIdentity(self.zone:getId(), self.zone:getName())
        self.discovery:start()
    else
        print("[ShelfOS] Network: no modem found")
        self.channel = nil
    end
end

-- Main run loop
function Kernel:run()
    if #self.monitors == 0 then
        -- Boot already handled this message
        return false
    end

    self.running = true

    -- Create parallel tasks
    local tasks = {}

    -- Monitor render tasks
    for _, monitor in ipairs(self.monitors) do
        table.insert(tasks, function()
            self:monitorLoop(monitor)
        end)
    end

    -- Menu handler
    table.insert(tasks, function()
        self:menuLoop()
    end)

    -- Network task (if available)
    if self.channel then
        table.insert(tasks, function()
            self:networkLoop()
        end)
    end

    -- Run all tasks
    parallel.waitForAny(table.unpack(tasks))

    self:shutdown()
end

-- Per-monitor render loop
function Kernel:monitorLoop(monitor)
    while self.running do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "monitor_touch" then
            monitor:handleTouch(p1, p2, p3)
        elseif event == "timer" then
            monitor:handleTimer(p1)
        end
    end
end

-- Menu handler loop
function Kernel:menuLoop()
    while self.running do
        local event, key = os.pullEvent("key")

        local action = Menu.handleKey(key)

        if action == "quit" then
            self.running = false
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
                sleep(1)
                self.running = false
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

            if result == "link_new" then
                self:createNetwork()
            elseif result == "link_join" and code then
                self:joinNetwork(code)
            elseif result == "link_disconnect" then
                self.config.network.enabled = false
                self.config.network.secret = nil
                Config.save(self.config)
                print("[ShelfOS] Disconnected from network.")
                sleep(1)
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
        sleep(2)
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

-- Join an existing network
function Kernel:joinNetwork(code)
    -- Check for modem
    local modem = peripheral.find("modem")
    if not modem then
        print("")
        print("[!] No modem found")
        sleep(2)
        return
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
        sleep(2)
        return
    end

    if response.type == "pair_response" and response.success then
        Config.setNetworkSecret(self.config, response.secret)
        self.config.zone.id = response.zoneId or self.config.zone.id
        Config.save(self.config)

        print("[*] Successfully joined network!")
        print("    Zone: " .. (response.zoneName or "Unknown"))
        sleep(2)
    else
        print("[!] Pairing failed: " .. (response.error or "Unknown error"))
        sleep(2)
    end

    rednet.close(modemName)
end

-- Network event loop
function Kernel:networkLoop()
    while self.running do
        if self.channel then
            self.channel:poll(0.5)

            -- Periodic announce
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
        else
            sleep(1)
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
