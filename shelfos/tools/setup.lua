-- setup.lua
-- Setup and reconfiguration wizard for ShelfOS

local Config = mpm('shelfos/core/Config')
local Zone = mpm('shelfos/core/Zone')
local ViewManager = mpm('views/Manager')
local Crypto = mpm('net/Crypto')

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
        print("    Zone: " .. (existingConfig.zone.name or "Unknown"))
        print("    Monitors: " .. #(existingConfig.monitors or {}))
        print("")
        print("Options:")
        print("  1. Reconfigure monitors")
        print("  2. Rename zone")
        print("  3. Reset everything")
        print("  4. Cancel")
        print("")
        write("Select (1-4): ")

        local choice = tonumber(read()) or 4

        if choice == 4 then
            print("[*] Cancelled")
            return
        elseif choice == 3 then
            fs.delete(Config.getPath())
            print("[*] Configuration deleted")
            existingConfig = nil
            isReconfigure = false
        elseif choice == 2 then
            print("")
            write("New zone name: ")
            local newName = read()
            if newName and #newName > 0 then
                existingConfig.zone.name = newName
                Config.save(existingConfig)
                print("[*] Zone renamed to: " .. newName)
            end
            return
        end
        -- choice == 1 falls through to monitor setup
        print("")
    end

    -- Zone setup
    print("=== Zone Configuration ===")
    print("")
    print("Zones are independent ShelfOS instances.")
    print("Each zone manages its own monitors.")
    print("")

    write("Zone name: ")
    local zoneName = read()
    if zoneName == "" then
        zoneName = "Zone " .. os.getComputerID()
    end

    local zoneId = Zone.generateId()
    print("Zone ID: " .. zoneId)
    print("")

    -- Monitor discovery
    print("=== Monitor Discovery ===")
    print("")
    print("Scanning for monitors...")

    local monitors = {}
    local peripherals = peripheral.getNames()

    for _, name in ipairs(peripherals) do
        if peripheral.hasType(name, "monitor") then
            local mon = peripheral.wrap(name)
            local w, h = mon.getSize()
            print("  [+] " .. name .. " (" .. w .. "x" .. h .. ")")
            table.insert(monitors, name)
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

    local mountableViews = ViewManager.getMountableViews()

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

    -- Network setup
    print("=== Network Configuration ===")
    print("")
    print("ShelfOS can communicate with pocket computers")
    print("and other zones over rednet.")
    print("")

    write("Enable networking? (y/n): ")
    local enableNetwork = read():lower() == "y"

    local networkSecret = nil

    if enableNetwork then
        -- Check for modem
        local hasModem = peripheral.find("modem") ~= nil

        if not hasModem then
            print("[!] No modem found. Networking disabled.")
            enableNetwork = false
        else
            print("")
            print("RECOMMENDED: Use pocket pairing instead!")
            print("  1. Create swarm on pocket computer")
            print("  2. Press L -> Accept from pocket")
            print("")
            print("Manual setup (advanced):")
            print("")

            write("Generate secret manually? (y/n): ")
            if read():lower() == "y" then
                networkSecret = Crypto.generateSecret()
                print("")
                print("Generated secret:")
                print("")
                print("  " .. networkSecret)
                print("")
                print("NOTE: Pocket pairing is easier!")
                print("This secret must match your pocket.")
                print("")
                write("Press Enter to continue...")
                read()
            else
                print("")
                write("Enter secret from pocket: ")
                networkSecret = read()

                if #networkSecret < 16 then
                    print("[!] Secret too short. Networking disabled.")
                    enableNetwork = false
                    networkSecret = nil
                end
            end
        end
    end

    print("")

    -- Create configuration
    print("=== Saving Configuration ===")
    print("")

    local config = Config.create(zoneId, zoneName)
    config.monitors = monitorConfigs

    if enableNetwork and networkSecret then
        Config.setNetworkSecret(config, networkSecret)
    end

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
