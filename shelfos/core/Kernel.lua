-- Kernel.lua
-- ShelfOS top-level runtime facade.

local Config = mpm('shelfos/core/Config')
local KernelBoot = mpm('shelfos/core/KernelBoot')
local KernelDispatcher = mpm('shelfos/core/KernelDispatcher')
local Terminal = mpm('shelfos/core/Terminal')
local KernelNetwork = mpm('shelfos/core/KernelNetwork')
local KernelMenu = mpm('shelfos/core/KernelMenu')
local ViewManager = mpm('views/Manager')
local MachineActivity = mpm('peripherals/MachineActivity')
local Yield = mpm('utils/Yield')

local Kernel = {}
Kernel.__index = Kernel

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
    self.dashboard = nil
    self.pairingActive = false
    self.bootMode = "unknown"

    return self
end

function Kernel:boot()
    return KernelBoot.boot(self)
end

function Kernel:initializeMonitors()
    KernelBoot.initializeMonitors(self)
end

function Kernel:persistViewChange(peripheralName, viewName, viewConfig)
    if Config.setMonitorView(self.config, peripheralName, viewName, viewConfig) then
        Config.save(self.config)
    end
    self:announceDiscovery()
end

function Kernel:announceDiscovery()
    if not self.discovery then
        return
    end
    local monitorInfo = {}
    for _, m in ipairs(self.monitors or {}) do
        table.insert(monitorInfo, {
            name = m:getName(),
            view = m:getViewName()
        })
    end
    self.discovery:announce(monitorInfo)
    if self.dashboard then
        self.dashboard:markActivity("announce", "Swarm metadata announce", colors.cyan)
    end
end

function Kernel:initializeNetwork()
    self.channel, self.discovery, self.peripheralHost, self.peripheralClient =
        KernelNetwork.initialize(self, self.config, self.identity)
end

function Kernel:recoverDetachedMonitor(attachedPeripheral)
    if not attachedPeripheral or self:getMonitor(attachedPeripheral) then
        return false
    end

    local isMonitor = false
    local okType = pcall(function()
        isMonitor = peripheral.hasType(attachedPeripheral, "monitor") == true
    end)
    if not okType or not isMonitor then
        return false
    end

    for _, monitor in ipairs(self.monitors) do
        if not monitor:isConnected() then
            local oldPeripheral = monitor:getPeripheralName()
            local adopted = monitor:adoptPeripheralName(attachedPeripheral)
            if adopted then
                if Config.renameMonitor(self.config, oldPeripheral, attachedPeripheral) then
                    Config.save(self.config)
                end
                if self.dashboard then
                    self.dashboard:setMessage("Monitor recovered: " .. oldPeripheral .. " -> " .. attachedPeripheral, colors.lime)
                    self.dashboard:requestRedraw()
                end
                return true
            end
        end
    end

    return false
end

function Kernel:run()
    KernelDispatcher.run(self)
end

function Kernel:keyboardLoop(runningRef)
    local function emitDashboardEvent(eventName, detail)
        pcall(os.queueEvent, "dashboard_event", {
            event = eventName,
            detail = detail
        })
    end

    while runningRef.value do
        local waitStart = os.epoch("utc")
        local event, p1 = Yield.waitForEvent(function(ev)
            local name = ev[1]
            return name == "key" or name == "peripheral" or name == "peripheral_detach"
        end)
        local waitDuration = os.epoch("utc") - waitStart
        local handlerStart = os.epoch("utc")

        if event == "key" then
            if self.pairingActive then
                goto continue
            end
            emitDashboardEvent("key", keys.getName(p1))
            KernelMenu.handleKey(self, p1, runningRef)
            if self.dashboard then
                self.dashboard:requestRedraw()
            end

        elseif event == "peripheral" or event == "peripheral_detach" then
            emitDashboardEvent(event, p1)
            ViewManager.invalidateMountableCache()
            MachineActivity.invalidateCache()

            local recoveredMonitor = false
            if event == "peripheral" then
                recoveredMonitor = self:recoverDetachedMonitor(p1)
            end

            if self.peripheralHost then
                self.peripheralHost:rescan()
                if self.dashboard and not recoveredMonitor then
                    local action = (event == "peripheral") and "attached" or "detached"
                    self.dashboard:setMessage("Peripheral " .. action .. ": " .. tostring(p1), colors.lightBlue)
                end
            end
            self:announceDiscovery()
        end

        if self.dashboard then
            self.dashboard:recordEventWaitMs(waitDuration)
            self.dashboard:recordHandlerMs(os.epoch("utc") - handlerStart)
        end
        ::continue::
    end
end

function Kernel:dashboardLoop(runningRef)
    while runningRef.value do
        local event, p1 = Yield.waitForEvent(function(ev)
            local name = ev[1]
            return name == "dashboard_dirty" or name == "term_resize" or name == "dashboard_event"
        end)

        if event == "dashboard_dirty" then
            if self.dashboard and not Terminal.isDialogOpen() and not self.pairingActive then
                self.dashboard:tick()
                if self.dashboard:shouldRender() then
                    self.dashboard:render(self)
                end
            end
        elseif event == "term_resize" then
            if not Terminal.isDialogOpen() then
                Terminal.resize()
                KernelMenu.draw()
                if self.dashboard then
                    self.dashboard:requestRedraw()
                    self.dashboard:render(self)
                end
            else
                if self.dashboard then
                    self.dashboard:requestRedraw()
                end
            end
        elseif event == "dashboard_event" then
            if self.dashboard then
                local detail = p1 or {}
                self.dashboard:recordLocalEvent(detail.event, detail.detail)
            end
        end
    end
end

function Kernel:getMonitor(peripheralName)
    for _, monitor in ipairs(self.monitors) do
        if monitor.peripheralName == peripheralName then
            return monitor
        end
    end
    return nil
end

function Kernel:shutdown()
    term.redirect(term.native())
    term.clear()
    term.setCursorPos(1, 1)

    Config.save(self.config)
    KernelNetwork.close(self.channel)

    for _, monitor in ipairs(self.monitors) do
        monitor:clear()
    end

    print("[ShelfOS] Shutdown complete.")
end

function Kernel:reload()
    KernelBoot.reload(self)
end

return Kernel
