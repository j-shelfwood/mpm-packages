-- Menu.lua
-- Interactive terminal menu for ShelfOS

local Menu = {}

-- Menu items definition
local menuItems = {
    { key = "s", label = "Status", action = "status" },
    { key = "l", label = "Link", action = "link" },
    { key = "r", label = "Reset", action = "reset" },
    { key = "q", label = "Quit", action = "quit" }
}

-- Draw the menu bar at current cursor position
function Menu.draw()
    local w, h = term.getSize()

    -- Build menu string
    local parts = {}
    for _, item in ipairs(menuItems) do
        table.insert(parts, "[" .. item.key:upper() .. "] " .. item.label)
    end
    local menuStr = table.concat(parts, "  ")

    -- Center it
    local x = math.floor((w - #menuStr) / 2) + 1

    term.setTextColor(colors.lightGray)
    term.setCursorPos(x, h)
    term.write(menuStr)
    term.setTextColor(colors.white)
end

-- Show status info
function Menu.showStatus(config)
    term.clear()
    term.setCursorPos(1, 1)

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

-- Show link menu
function Menu.showLink(config)
    term.clear()
    term.setCursorPos(1, 1)

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

    if key == keys.one then
        if config.network.enabled then
            -- Show pairing code
            print("")
            print("Pairing code: " .. (config.network.pairingCode or "N/A"))
            print("")
            print("Press any key...")
            os.pullEvent("key")
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
            end
        end
    end

    return nil
end

-- Show reset confirmation
function Menu.showReset()
    term.clear()
    term.setCursorPos(1, 1)

    print("=== Reset ShelfOS ===")
    print("")
    print("This will delete your configuration.")
    print("ShelfOS will auto-configure on next boot.")
    print("")
    print("Are you sure? (y/n)")

    local event, key = os.pullEvent("key")

    if key == keys.y then
        return true
    end

    return false
end

-- Handle a keypress, return action or nil
function Menu.handleKey(key)
    local keyName = keys.getName(key)

    if not keyName then
        return nil
    end

    keyName = keyName:lower()

    for _, item in ipairs(menuItems) do
        if item.key == keyName then
            return item.action
        end
    end

    return nil
end

-- Redraw terminal header with zone info
function Menu.drawHeader(zone, monitorCount)
    term.clear()
    term.setCursorPos(1, 1)

    term.setTextColor(colors.cyan)
    print("ShelfOS - " .. (zone and zone:getName() or "Unknown Zone"))
    term.setTextColor(colors.lightGray)
    print(monitorCount .. " monitor(s) active | Touch monitors to cycle views")
    term.setTextColor(colors.white)
    print("")
end

return Menu
