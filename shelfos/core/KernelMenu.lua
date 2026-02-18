-- KernelMenu.lua
-- Menu key handling for Kernel
-- Processes terminal keyboard input and dispatches to dialogs
-- Extracted from Kernel.lua for maintainability

local Config = mpm('shelfos/core/Config')
local Paths = mpm('shelfos/core/Paths')
local Terminal = mpm('shelfos/core/Terminal')
local Menu = mpm('shelfos/input/Menu')
local ViewManager = mpm('views/Manager')

local KernelMenu = {}

-- Draw the menu bar
-- @param terminal Terminal module (for drawMenu)
function KernelMenu.draw()
    Terminal.drawMenu({
        { key = "m", label = "Monitors" },
        { key = "s", label = "Status" },
        { key = "l", label = "Link" },
        { key = "r", label = "Reset" },
        { key = "q", label = "Quit" }
    })
end

-- Handle menu key press
-- @param kernel Kernel instance
-- @param key Key code pressed
-- @param runningRef Shared running flag table { value = true/false }
function KernelMenu.handleKey(kernel, key, runningRef)
    local action = Menu.handleKey(key)

    if action == "quit" then
        runningRef.value = false
        return

    elseif action == "status" then
        Terminal.showDialog(function()
            Menu.showStatus(kernel.config)
        end)
        Terminal.clearLog()
        KernelMenu.draw()

    elseif action == "reset" then
        local confirmed = Terminal.showDialog(function()
            return Menu.showReset()
        end)

        if confirmed then
            KernelMenu.doFactoryReset(kernel)
            -- Never returns (reboots)
        else
            Terminal.clearLog()
            KernelMenu.draw()
        end

    elseif action == "link" then
        local result, code = Terminal.showDialog(function()
            return Menu.showLink(kernel.config)
        end)

        Terminal.clearLog()

        if result == "link_pocket_accept" then
            local KernelPairing = mpm('shelfos/core/KernelPairing')
            KernelPairing.acceptFromPocket(kernel)
            KernelMenu.draw()
        elseif result == "link_disconnect" then
            KernelMenu.doLeaveSwarm(kernel)
            -- Never returns (reboots)
        else
            KernelMenu.draw()
        end

    elseif action == "monitors" then
        local availableViews = ViewManager.getMountableViews()

        local result, monitorIndex, newView = Terminal.showDialog(function()
            return Menu.showMonitors(kernel.monitors, availableViews)
        end)

        Terminal.clearLog()

        if result == "change_view" and monitorIndex and newView then
            local monitor = kernel.monitors[monitorIndex]
            if monitor then
                monitor:loadView(newView)
                kernel:persistViewChange(monitor:getPeripheralName(), newView)
                if kernel.dashboard then
                    kernel.dashboard:setMessage("View changed: " .. monitor:getName() .. " -> " .. newView, colors.lime)
                else
                    print("[ShelfOS] " .. monitor:getName() .. " -> " .. newView)
                end
            end
        end

        KernelMenu.draw()
    end
end

-- Factory reset: delete everything and reboot
-- @param kernel Kernel instance
function KernelMenu.doFactoryReset(kernel)
    -- 1. Clear monitors visually
    for _, monitor in ipairs(kernel.monitors) do
        monitor:clear()
    end

    -- 2. Close network
    if kernel.channel then
        rednet.unhost("shelfos")
        kernel.channel:close()
    end

    -- 3. Clear crypto state
    local Crypto = mpm('net/Crypto')
    Crypto.clearSecret()

    -- 4. Delete ALL config files
    Paths.deleteFiles()

    -- 5. Restore terminal and show message
    term.redirect(term.native())
    term.clear()
    term.setCursorPos(1, 1)
    print("=====================================")
    print("   FACTORY RESET")
    print("=====================================")
    print("")
    print("Configuration deleted.")
    print("Rebooting in 2 seconds...")

    -- 6. HARD REBOOT - prevents any save-on-exit from running
    sleep(2)
    os.reboot()
    -- Code never reaches here
end

-- Leave swarm: clear credentials and reboot
-- @param kernel Kernel instance
function KernelMenu.doLeaveSwarm(kernel)
    -- 1. Clear monitors
    for _, monitor in ipairs(kernel.monitors) do
        monitor:clear()
    end

    -- 2. Close network
    if kernel.channel then
        rednet.unhost("shelfos")
        kernel.channel:close()
    end

    -- 3. Clear crypto state
    local Crypto = mpm('net/Crypto')
    Crypto.clearSecret()

    -- 4. Update and save config (keep monitors, clear network)
    kernel.config.network.enabled = false
    kernel.config.network.secret = nil
    Config.save(kernel.config)

    -- 5. Restore terminal and show message
    term.redirect(term.native())
    term.clear()
    term.setCursorPos(1, 1)
    print("=====================================")
    print("   LEFT SWARM")
    print("=====================================")
    print("")
    print("Network credentials cleared.")
    print("Rebooting in 2 seconds...")

    -- 6. REBOOT for clean state
    sleep(2)
    os.reboot()
    -- Code never reaches here
end

return KernelMenu
