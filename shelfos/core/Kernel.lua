-- Kernel.lua
-- Main event loop and system orchestration
-- Menu handling uses Controller abstraction for unified terminal/monitor support
--
-- Split modules:
--   KernelNetwork.lua  - Network initialization and loop
--   KernelPairing.lua  - Pocket pairing flow
--   KernelMenu.lua     - Terminal menu key handlers

local Config = mpm('shelfos/core/Config')
local Monitor = mpm('shelfos/core/Monitor')
local Identity = mpm('shelfos/core/Identity')
local Terminal = mpm('shelfos/core/Terminal')
local KernelNetwork = mpm('shelfos/core/KernelNetwork')
local KernelMenu = mpm('shelfos/core/KernelMenu')
local AESnapshotBus = mpm('peripherals/AESnapshotBus')
local ViewManager = mpm('views/Manager')
local MachineActivity = mpm('peripherals/MachineActivity')
-- Note: TimerDispatch no longer needed - parallel API gives each coroutine its own event queue

local Kernel = {}
Kernel.__index = Kernel

-- Create a new kernel instance
function Kernel.new()
    local self = setmetatable({}, Kernel)
    self.config = nil
    self.identity = nil
    self.monitors = {}
    self.running = false
    self.channel = nil
    self.discovery = nil
    self.peripheralHost = nil
    self.peripheralClient = nil

    return self
end

-- Boot the system
function Kernel:boot()
    -- Initialize terminal windows (log area + menu bar)
    Terminal.init()
    Terminal.clearAll()

    -- Clear any stale crypto state from previous session FIRST
    -- _G persists across program restarts in CC:Tweaked
    local Crypto = mpm('net/Crypto')
    Crypto.clearSecret()

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
        -- Note: "Not in swarm" message is printed by KernelNetwork.initialize()
    else
        -- Reconcile existing config against actual hardware
        -- Fixes duplicate entries, remaps aliased names, adds new monitors
        local reconciled, summary = Config.reconcile(self.config)
        if reconciled then
            Config.save(self.config)
            print("[ShelfOS] Config healed: " .. summary)
        end
    end

    -- Initialize computer identity
    self.identity = Identity.new(self.config.computer)
    print("[ShelfOS] Computer: " .. self.identity:getName())

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
    KernelMenu.draw()

    return true
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

-- Initialize networking (delegates to KernelNetwork module)
function Kernel:initializeNetwork()
    self.channel, self.discovery, self.peripheralHost, self.peripheralClient =
        KernelNetwork.initialize(self, self.config, self.identity)
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
            KernelNetwork.loop(self, runningRef)
        end)
    end

    -- Shared AE snapshot poller (decouples heavy peripheral reads from view renders)
    table.insert(tasks, function()
        AESnapshotBus.runLoop(runningRef)
    end)

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
            KernelMenu.handleKey(self, p1, runningRef)

        elseif event == "peripheral" or event == "peripheral_detach" then
            ViewManager.invalidateMountableCache()
            MachineActivity.invalidateCache()

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

-- Get a monitor by peripheral name (alias)
function Kernel:getMonitor(peripheralName)
    for _, monitor in ipairs(self.monitors) do
        if monitor.peripheralName == peripheralName then
            return monitor
        end
    end
    return nil
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
    KernelNetwork.close(self.channel)

    -- Clear monitors
    for _, monitor in ipairs(self.monitors) do
        monitor:clear()
    end

    print("[ShelfOS] Goodbye!")
end

-- Reload configuration
function Kernel:reload()
    print("[ShelfOS] Reloading configuration...")
    self.config = Config.load()
    self:initializeMonitors()
end

return Kernel
