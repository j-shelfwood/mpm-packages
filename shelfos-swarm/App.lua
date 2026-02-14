-- App.lua
-- ShelfOS Swarm - Pocket computer swarm controller
-- The "queen" of the swarm - manages zone registration and revocation
--
-- Screen modules:
--   screens/AddZone.lua     - Zone pairing flow
--   screens/ViewZones.lua   - Zone registry display
--   screens/DeleteSwarm.lua - Swarm deletion confirmation

local SwarmAuthority = mpm('shelfos-swarm/core/SwarmAuthority')
local Paths = mpm('shelfos-swarm/core/Paths')

-- Screen modules
local AddZone = mpm('shelfos-swarm/screens/AddZone')
local ViewZones = mpm('shelfos-swarm/screens/ViewZones')
local DeleteSwarm = mpm('shelfos-swarm/screens/DeleteSwarm')

local App = {}
App.__index = App

function App.new()
    local self = setmetatable({}, App)
    self.authority = SwarmAuthority.new()
    self.channel = nil
    self.discovery = nil
    self.running = false
    self.modemType = nil

    return self
end

-- Initialize the app
function App:init()
    term.clear()
    term.setCursorPos(1, 1)

    print("=====================================")
    print("      ShelfOS Swarm Controller")
    print("=====================================")
    print("")

    -- Check for modem
    local modem = peripheral.find("modem")
    if not modem then
        print("[!] No modem found")
        print("    Attach a wireless or ender modem")
        print("")
        print("Press any key to exit...")
        os.pullEvent("key")
        return false
    end

    self.modemType = modem.isWireless() and "wireless" or "wired"
    print("[+] Modem: " .. self.modemType)

    -- Check if swarm exists
    if self.authority:exists() then
        local ok = self.authority:init()
        if ok then
            local info = self.authority:getInfo()
            print("[+] Swarm: " .. info.name)
            print("    Zones: " .. info.zoneCount)
            print("    Fingerprint: " .. info.fingerprint)
        else
            print("[!] Failed to load swarm")
            print("    Data may be corrupted")
            print("")
            print("[R] Reset and create new swarm")
            print("[Q] Quit")

            while true do
                local _, key = os.pullEvent("key")
                if key == keys.r then
                    self.authority:deleteSwarm()
                    print("[*] Swarm deleted, restarting...")
                    sleep(1)
                    os.reboot()
                elseif key == keys.q then
                    return false
                end
            end
        end
    else
        print("[-] No swarm configured")
        print("")
        print("[C] Create new swarm")
        print("[Q] Quit")

        while true do
            local _, key = os.pullEvent("key")
            if key == keys.c then
                return self:createSwarm()
            elseif key == keys.q then
                return false
            end
        end
    end

    -- Initialize networking
    local netOk, netErr = self:initNetwork()
    if netOk then
        print("[+] Network ready")
    else
        print("[!] Network: " .. (netErr or "failed"))
    end

    return true
end

-- Create a new swarm
function App:createSwarm()
    term.clear()
    term.setCursorPos(1, 1)

    print("=====================================")
    print("        Create New Swarm")
    print("=====================================")
    print("")

    print("Enter swarm name:")
    write("> ")
    local name = read()

    if not name or #name == 0 then
        name = "My Swarm"
    end

    print("")
    print("Creating swarm...")

    local ok, swarmId = self.authority:createSwarm(name)
    if not ok then
        print("[!] Failed to create swarm")
        sleep(2)
        return false
    end

    local info = self.authority:getInfo()

    print("")
    print("[+] Swarm created!")
    print("")
    print("    Name: " .. info.name)
    print("    ID: " .. info.id)
    print("    Fingerprint: " .. info.fingerprint)
    print("")
    print("This fingerprint identifies your swarm.")
    print("Zones will display it after pairing.")
    print("")
    print("Press any key to continue...")
    os.pullEvent("key")

    -- Initialize networking
    local netOk, netErr = self:initNetwork()
    if not netOk then
        print("[!] Network warning: " .. (netErr or "unknown"))
        sleep(2)
    end

    return true
end

-- Initialize networking
function App:initNetwork()
    local modem = peripheral.find("modem")
    if not modem then
        return false, "No modem found"
    end

    local modemName = peripheral.getName(modem)
    if not modemName then
        return false, "Could not get modem name"
    end

    -- Try to open modem with error handling
    local ok, err = pcall(function()
        if not rednet.isOpen(modemName) then
            rednet.open(modemName)
        end
    end)

    if not ok then
        return false, "Failed to open modem: " .. tostring(err)
    end

    -- Register with service discovery
    local info = self.authority:getInfo()
    if info then
        rednet.host("shelfos_swarm", info.id)
    end

    return true
end

-- Draw main menu
function App:drawMenu()
    term.clear()
    term.setCursorPos(1, 1)

    local info = self.authority:getInfo()

    print("=====================================")
    print("  " .. (info and info.name or "ShelfOS Swarm"))
    print("=====================================")
    print("")

    if info then
        print("Fingerprint: " .. info.fingerprint)
        print("Zones: " .. info.zoneCount .. " active")
    end

    print("")
    print("-------------------")
    print("[A] Add Zone")
    print("[Z] View Zones")
    print("[D] Delete Swarm")
    print("[Q] Quit")
    print("-------------------")
end

-- Run main loop
function App:run()
    self.running = true

    while self.running do
        self:drawMenu()

        local _, key = os.pullEvent("key")

        if key == keys.q then
            self.running = false
        elseif key == keys.a then
            AddZone.run(self)
        elseif key == keys.z then
            ViewZones.run(self)
        elseif key == keys.d then
            DeleteSwarm.run(self)
        end
    end

    self:shutdown()
end

-- Shutdown
function App:shutdown()
    rednet.unhost("shelfos_swarm")
    term.clear()
    term.setCursorPos(1, 1)
    print("ShelfOS Swarm stopped.")
end

return App
