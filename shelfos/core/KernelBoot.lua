local Config = mpm('shelfos/core/Config')
local Identity = mpm('shelfos/core/Identity')
local Terminal = mpm('shelfos/core/Terminal')
local TerminalDashboard = mpm('shelfos/core/TerminalDashboard')
local Monitor = mpm('shelfos/core/Monitor')
local KernelMenu = mpm('shelfos/core/KernelMenu')
local KernelNetwork = mpm('shelfos/core/KernelNetwork')
local ViewManager = mpm('views/Manager')
local ViewCleanup = mpm('views/Cleanup')

local KernelBoot = {}

local function countConnectedMonitors(monitors)
    local connected = 0
    for _, monitor in ipairs(monitors or {}) do
        if monitor:isConnected() then
            connected = connected + 1
        end
    end
    return connected
end

function KernelBoot.determineMode(kernel)
    local monitorCount = #(kernel.config and kernel.config.monitors or {})
    local hasSecret = kernel.config and kernel.config.network and kernel.config.network.secret

    if not hasSecret then
        return "pairing"
    end
    if monitorCount == 0 then
        return "terminal"
    end
    return "runtime"
end

function KernelBoot.initializeMonitors(kernel)
    kernel.monitors = {}

    local function onViewChange(peripheralName, viewName, viewConfig)
        kernel:persistViewChange(peripheralName, viewName, viewConfig)
    end

    if not kernel.config or not kernel.config.monitors or #kernel.config.monitors == 0 then
        if kernel.dashboard then
            kernel.dashboard:requestRedraw()
        end
        return
    end

    local settings = kernel.config.settings or {}
    local availableViews = ViewManager.getSelectableViews()

    for i, monitorConfig in ipairs(kernel.config.monitors or {}) do
        local ok, monitorOrErr = pcall(Monitor.new, monitorConfig, onViewChange, settings, i - 1, availableViews)
        if not ok then
            local msg = "Monitor init failed: " .. tostring(monitorConfig.peripheral) .. " (" .. tostring(monitorOrErr) .. ")"
            print("[ShelfOS] " .. msg)
            if kernel.dashboard then
                kernel.dashboard:setMessage(msg, colors.red)
            end
        else
            local monitor = monitorOrErr
            table.insert(kernel.monitors, monitor)
            if not monitor:isConnected() and kernel.dashboard then
                kernel.dashboard:setMessage("Monitor not connected (will retry): " .. monitorConfig.peripheral, colors.orange)
            end
        end
    end

    if kernel.dashboard then
        kernel.dashboard:requestRedraw()
    end
    kernel:announceDiscovery()
end

function KernelBoot.boot(kernel)
    Terminal.init()
    Terminal.clearAll()
    kernel.dashboard = TerminalDashboard.new()
    kernel.dashboard:setMessage("Booting ShelfOS...", colors.lightGray)
    kernel.dashboard:render(kernel)

    local Crypto = mpm('net/Crypto')
    Crypto.clearSecret()

    kernel.config = Config.load()

    if not kernel.config then
        kernel.dashboard:setMessage("First boot: discovering peripherals...", colors.yellow)
        local discoveredMonitors = Config.discoverMonitors()
        if #discoveredMonitors > 0 then
            kernel.config, kernel.discoveredCount = Config.autoCreate()
            kernel.dashboard:setMessage("Auto-configured " .. kernel.discoveredCount .. " monitor(s)", colors.lime)
        else
            kernel.config = Config.create(
                "computer_" .. os.getComputerID() .. "_" .. os.epoch("utc"),
                os.getComputerLabel() or ("Computer " .. os.getComputerID())
            )
            kernel.discoveredCount = 0
            kernel.dashboard:setMessage("No monitors detected; running terminal-only mode", colors.orange)
        end

        Config.save(kernel.config)
    else
        local reconciled, summary = Config.reconcile(kernel.config)
        if reconciled then
            Config.save(kernel.config)
            kernel.dashboard:setMessage("Config healed: " .. summary, colors.yellow)
        end
    end

    kernel.identity = Identity.new(kernel.config.computer)
    kernel.dashboard:setIdentity(kernel.identity:getName(), kernel.identity:getId())

    -- Prune optional view packages that are no longer used by any monitor
    local pruned = ViewCleanup.pruneUnused(kernel.config)
    if pruned > 0 then
        kernel.dashboard:setMessage("Pruned " .. pruned .. " unused view package(s)", colors.yellow)
    end

    kernel.dashboard:setMessage("Initializing network...", colors.lightGray)

    kernel:initializeNetwork()
    KernelBoot.initializeMonitors(kernel)

    KernelMenu.draw()
    local connectedMonitors = countConnectedMonitors(kernel.monitors)
    if connectedMonitors == 0 then
        kernel.dashboard:setMessage("Dashboard online. Network/peripheral host active (0 monitors)", colors.orange)
    else
        kernel.dashboard:setMessage("Dashboard online. " .. connectedMonitors .. " monitor(s) active.", colors.lime)
    end

    kernel.bootMode = KernelBoot.determineMode(kernel)
    kernel.dashboard:render(kernel)

    return true
end

function KernelBoot.reload(kernel)
    if kernel.dashboard then
        kernel.dashboard:setMessage("Reloading configuration...", colors.lightGray)
    end
    kernel.config = Config.load()
    KernelBoot.initializeMonitors(kernel)
end

return KernelBoot
