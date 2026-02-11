-- Menu.lua
-- Menu dialogs and key handling for ShelfOS

local Menu = {}

-- Menu key mappings
local menuKeys = {
    s = "status",
    l = "link",
    r = "reset",
    q = "quit"
}

-- Handle a keypress, return action or nil
function Menu.handleKey(key)
    local keyName = keys.getName(key)

    if not keyName then
        return nil
    end

    return menuKeys[keyName:lower()]
end

-- Show status dialog (called within Terminal.showDialog)
function Menu.showStatus(config)
    print("=== ShelfOS Status ===")
    print("")
    print("Zone: " .. (config.zone.name or "Unknown"))
    print("Zone ID: " .. (config.zone.id or "N/A"))
    print("")
    print("Monitors (" .. #(config.monitors or {}) .. "):")
    for _, m in ipairs(config.monitors or {}) do
        print("  " .. m.peripheral .. " -> " .. m.view)
    end
    print("")
    print("Network: " .. (config.network.enabled and "enabled" or "standalone"))
    if config.network.pairingCode then
        print("Pairing code: " .. config.network.pairingCode)
    end
    print("")
    print("Press any key to continue...")
    os.pullEvent("key")
end

-- Show reset confirmation dialog
function Menu.showReset()
    print("=== Reset ShelfOS ===")
    print("")
    print("This will delete your configuration.")
    print("ShelfOS will auto-configure on next boot.")
    print("")
    print("Are you sure? (y/n)")

    local event, key = os.pullEvent("key")

    return key == keys.y
end

-- Show link menu dialog
function Menu.showLink(config)
    print("=== Network Link ===")
    print("")

    if config.network.enabled then
        print("Status: Connected to network")
        print("")
        print("[1] Show pairing code")
        print("[2] Disconnect from network")
        print("[3] Back")
    else
        print("Status: Standalone (not linked)")
        print("")
        if config.network.pairingCode then
            print("Your pairing code: " .. config.network.pairingCode)
            print("")
        end
        print("[1] Create new network")
        print("[2] Join existing network")
        print("[3] Back")
    end

    print("")
    write("Choice: ")

    local event, key = os.pullEvent("key")
    print("")

    if key == keys.one then
        if config.network.enabled then
            -- Show pairing code
            print("Pairing code: " .. (config.network.pairingCode or "N/A"))
            print("")
            print("Press any key...")
            os.pullEvent("key")
            return nil
        else
            -- Create new network
            return "link_new"
        end
    elseif key == keys.two then
        if config.network.enabled then
            -- Disconnect
            return "link_disconnect"
        else
            -- Join network
            print("")
            write("Enter pairing code: ")
            local code = read()
            if code and #code >= 8 then
                return "link_join", code
            else
                print("Invalid code")
                sleep(1)
            end
        end
    end

    return nil
end

return Menu
