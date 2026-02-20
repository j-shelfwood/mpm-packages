-- setup.lua
-- Setup and reconfiguration wizard for ShelfOS

local Config = mpm('shelfos/core/Config')
local Paths = mpm('shelfos/core/Paths')
local Identity = mpm('shelfos/core/Identity')
local ViewManager = mpm('views/Manager')
local Crypto = mpm('net/Crypto')
local Yield = mpm('utils/Yield')

local setup = {}

-- Run the setup wizard
function setup.run()
    term.clear()
    term.setCursorPos(1, 1)

    print("================================")
    print("  ShelfOS Setup Wizard")
    print("================================")
    print("")

    -- Check for existing config
    local existingConfig = Config.load()
    local isReconfigure = existingConfig ~= nil

    if isReconfigure then
        print("[*] Existing configuration found")
        print("    Computer: " .. (existingConfig.computer.name or "Unknown"))
        print("    Monitors: " .. #(existingConfig.monitors or {}))
        print("")
        print("Options:")
        print("  1. Reconfigure monitors")
        print("  2. Rename computer")
        print("  3. Reset everything")
        print("  4. Cancel")
        print("")
        write("Select (1-4): ")

        local choice = tonumber(read()) or 4

        if choice == 4 then
            print("[*] Cancelled")
            return
        elseif choice == 3 then
            -- Factory reset
            Crypto.clearSecret()
            Paths.deleteFiles()

            print("")
            print("=====================================")
            print("   FACTORY RESET")
            print("=====================================")
            print("")
            print("Configuration deleted.")
            print("Rebooting in 2 seconds...")
            Yield.sleep(2)
            os.reboot()
        elseif choice == 2 then
            print("")
            write("New computer name: ")
            local newName = read()
            if newName and #newName > 0 then
                existingConfig.computer.name = newName
                Config.save(existingConfig)
                print("[*] Computer renamed to: " .. newName)
            end
            return
        end
        -- choice == 1 falls through to monitor setup
        print("")
    end

    -- Computer setup
    print("=== Computer Configuration ===")
    print("")
    print("Each ShelfOS instance manages its own monitors.")
    print("")

    write("Computer name: ")
    local computerName = read()
    if computerName == "" then
        computerName = "Computer " .. os.getComputerID()
    end

    local computerId = Identity.generateId()
    print("Computer ID: " .. computerId)
    print("")

    -- Monitor discovery
    print("=== Monitor Discovery ===")
    print("")
    print("Scanning for monitors...")

    local monitors = Config.discoverMonitors()
    for _, name in ipairs(monitors) do
        local mon = peripheral.wrap(name)
        if mon then
            local w, h = mon.getSize()
            print("  [+] " .. name .. " (" .. w .. "x" .. h .. ")")
        else
            print("  [+] " .. name)
        end
    end

    if #monitors == 0 then
        print("  [!] No monitors found")
        print("")
        print("Connect monitors and run setup again.")
        return
    end

    print("")
    print("Found " .. #monitors .. " monitor(s)")
    print("")

    -- View selection for each monitor
    print("=== View Assignment ===")
    print("")

    local mountableViews = ViewManager.getSelectableViews()

    if #mountableViews == 0 then
        print("[!] No views available.")
        print("    Install the views package: mpm install views")
        return
    end

    print("Available views:")
    for i, view in ipairs(mountableViews) do
        print("  " .. i .. ". " .. view)
    end
    print("")

    local monitorConfigs = {}

    for _, monitorName in ipairs(monitors) do
        print("View for " .. monitorName .. ":")
        write("  Enter number (1-" .. #mountableViews .. "): ")

        local input = read()
        local viewIndex = tonumber(input) or 1

        if viewIndex < 1 then viewIndex = 1 end
        if viewIndex > #mountableViews then viewIndex = #mountableViews end

        local viewName = mountableViews[viewIndex]
        print("  -> " .. viewName)

        table.insert(monitorConfigs, {
            peripheral = monitorName,
            label = monitorName,
            view = viewName,
            viewConfig = ViewManager.getDefaultConfig(viewName)
        })
    end

    print("")

    -- Network info
    print("=== Network Configuration ===")
    print("")
    print("To join a swarm (network with pocket):")
    print("")
    print("  1. Start ShelfOS: mpm run shelfos")
    print("  2. Press L -> Accept from pocket")
    print("  3. Pair from pocket computer")
    print("")
    print("Network is NOT configured by this wizard.")
    print("Pocket pairing is required for security.")
    print("")

    -- Create configuration
    print("=== Saving Configuration ===")
    print("")

    local config = Config.create(computerId, computerName)
    config.monitors = monitorConfigs
    -- Note: Network is NOT configured here - use pocket pairing

    local saved = Config.save(config)

    if saved then
        print("[*] Configuration saved to " .. Config.getPath())
        print("")
        print("=== Setup Complete ===")
        print("")
        print("Start ShelfOS with: mpm run shelfos")
        print("")
    else
        print("[!] Failed to save configuration")
    end
end

return setup
