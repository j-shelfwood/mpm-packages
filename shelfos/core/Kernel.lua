-- Kernel.lua
-- Main event loop and system orchestration

local Config = mpm('shelfos/core/Config')
local Monitor = mpm('shelfos/core/Monitor')
local Zone = mpm('shelfos/core/Zone')

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

        -- Save the auto-generated config
        Config.save(self.config)
        print("[ShelfOS] Auto-configured " .. self.discoveredCount .. " monitor(s)")

        -- Generate pairing code for network
        self.pairingCode = Config.generatePairingCode()
        print("[ShelfOS] Pairing code: " .. self.pairingCode)
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

    print("[ShelfOS] Boot complete. " .. #self.monitors .. " monitor(s) active.")
    print("[ShelfOS] Touch left/right to cycle views")
    print("[ShelfOS] Press 'q' to quit")
    print("")

    return true
end

-- Initialize all configured monitors
function Kernel:initializeMonitors()
    self.monitors = {}

    for _, monitorConfig in ipairs(self.config.monitors or {}) do
        local monitor = Monitor.new(monitorConfig)

        if monitor:isConnected() then
            table.insert(self.monitors, monitor)
            print("  [+] " .. monitor:getName() .. " -> " .. monitor:getViewName())
        else
            print("  [-] " .. monitorConfig.peripheral .. " (not connected)")
        end
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

    -- Key listener (quit on 'q')
    table.insert(tasks, function()
        self:keyListener()
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
        -- Handle touch events and render
        local event, p1, p2, p3 = os.pullEvent()

        if event == "monitor_touch" then
            monitor:handleTouch(p1, p2, p3)
        elseif event == "timer" then
            -- Check if this is our render timer
            if monitor:isRenderTimer(p1) then
                monitor:render()
                monitor:scheduleRender()
            end
        end
    end
end

-- Keyboard listener
function Kernel:keyListener()
    while self.running do
        local event, key = os.pullEvent("key")

        if key == keys.q then
            print("[ShelfOS] Quit requested")
            self.running = false
            return
        end
    end
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
