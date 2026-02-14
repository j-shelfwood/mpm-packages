-- App.lua
-- ShelfOS Swarm - Pocket computer swarm controller
-- The "queen" of the swarm - manages zone registration and revocation
--
-- Refactored to use ScreenManager for navigation and TermUI for rendering.
-- Init flow detects modem, loads/creates swarm, then pushes appropriate screen.
--
-- Screen modules:
--   screens/MainMenu.lua     - Main menu with swarm info
--   screens/CreateSwarm.lua  - Swarm creation wizard
--   screens/AddZone.lua      - Zone pairing flow
--   screens/ViewZones.lua    - Zone registry display
--   screens/DeleteSwarm.lua  - Swarm deletion confirmation

local SwarmAuthority = mpm('shelfos-swarm/core/SwarmAuthority')
local ScreenManager = mpm('shelfos-swarm/ui/ScreenManager')
local TermUI = mpm('shelfos-swarm/ui/TermUI')
local ModemUtils = mpm('utils/ModemUtils')

-- Screen modules (lazy loaded to avoid circular deps)
local MainMenu = mpm('shelfos-swarm/screens/MainMenu')
local CreateSwarm = mpm('shelfos-swarm/screens/CreateSwarm')

local App = {}
App.__index = App

function App.new()
    local self = setmetatable({}, App)
    self.authority = SwarmAuthority.new()
    self.modemType = nil
    self.initialScreen = nil

    return self
end

-- Initialize the app
-- Detects modem, loads or creates swarm, determines initial screen
-- @return true if ready to run, false to exit
function App:init()
    TermUI.clear()
    TermUI.drawTitleBar("ShelfOS Swarm")

    local y = 3

    -- Check for modem
    local modem, modemName, modemType = ModemUtils.find(true)
    if not modem then
        TermUI.drawText(2, y, "No modem found", colors.red)
        y = y + 2
        TermUI.drawWrapped(y, "Attach a wireless or ender modem to continue.", colors.lightGray, 2, 2)
        TermUI.drawStatusBar("Press any key to exit...")
        os.pullEvent("key")
        return false
    end

    self.modemType = modemType
    TermUI.drawInfoLine(y, "Modem", modemType, colors.lime)
    y = y + 1

    -- Check if swarm exists
    if self.authority:exists() then
        local ok = self.authority:init()
        if ok then
            local info = self.authority:getInfo()
            TermUI.drawInfoLine(y, "Swarm", info.name, colors.white)
            y = y + 1
            TermUI.drawInfoLine(y, "Zones", info.zoneCount .. " active", colors.lime)
            y = y + 1
            TermUI.drawInfoLine(y, "FP", info.fingerprint, colors.lightGray)
            y = y + 1

            -- Initialize networking
            local netOk, netErr = self:initNetwork()
            if netOk then
                TermUI.drawInfoLine(y, "Network", "ready", colors.lime)
            else
                TermUI.drawInfoLine(y, "Network", netErr or "failed", colors.orange)
            end

            self.initialScreen = MainMenu
            sleep(0.5)  -- Brief pause to show status
            return true
        else
            -- Corrupted swarm data
            TermUI.drawText(2, y, "Failed to load swarm", colors.red)
            y = y + 1
            TermUI.drawText(2, y, "Data may be corrupted", colors.orange)
            y = y + 2

            TermUI.drawMenuItem(y, "R", "Reset and create new")
            y = y + 1
            TermUI.drawMenuItem(y, "Q", "Quit")

            while true do
                local _, keyCode = os.pullEvent("key")
                local keyName = keys.getName(keyCode)
                if keyName then
                    keyName = keyName:lower()
                    if keyName == "r" then
                        self.authority:deleteSwarm()
                        TermUI.clear()
                        TermUI.drawCentered(10, "Swarm deleted, restarting...", colors.orange)
                        sleep(1)
                        os.reboot()
                    elseif keyName == "q" then
                        return false
                    end
                end
            end
        end
    else
        -- No swarm yet - go to setup flow
        TermUI.drawText(2, y, "No swarm configured", colors.lightGray)
        y = y + 2

        TermUI.drawMenuItem(y, "C", "Create new swarm")
        y = y + 1
        TermUI.drawMenuItem(y, "Q", "Quit")

        while true do
            local _, keyCode = os.pullEvent("key")
            local keyName = keys.getName(keyCode)
            if keyName then
                keyName = keyName:lower()
                if keyName == "c" then
                    self.initialScreen = CreateSwarm
                    return true
                elseif keyName == "q" then
                    return false
                end
            end
        end
    end
end

-- Initialize networking
function App:initNetwork()
    local ok, modemName, modemType = ModemUtils.open(true)
    if not ok then
        return false, "No modem found"
    end

    local info = self.authority:getInfo()
    if info then
        rednet.host("shelfos_swarm", info.id)
    end

    return true
end

-- Run the app with ScreenManager
function App:run()
    if not self.initialScreen then
        return
    end

    local manager = ScreenManager.new(self)
    manager:push(self.initialScreen)
    manager:run()

    self:shutdown()
end

-- Shutdown
function App:shutdown()
    rednet.unhost("shelfos_swarm")
    TermUI.clear()
    TermUI.drawCentered(10, "ShelfOS Swarm stopped.", colors.lightGray)
end

return App
