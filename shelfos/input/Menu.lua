-- Menu.lua
-- Menu dialogs and key handling for ShelfOS

local Menu = {}

-- Menu key mappings
local menuKeys = {
    m = "monitors",
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

-- Show monitors overview dialog
-- Returns: action, monitorIndex (e.g., "cycle_next", 1)
function Menu.showMonitors(monitors, availableViews)
    while true do
        term.clear()
        term.setCursorPos(1, 1)

        print("=== Monitors ===")
        print("")

        if #monitors == 0 then
            print("No monitors connected.")
            print("")
            print("Press any key to go back...")
            os.pullEvent("key")
            return nil
        end

        -- List monitors with numbers
        for i, monitor in ipairs(monitors) do
            local status = monitor:isConnected() and "" or " (disconnected)"
            print(string.format("[%d] %s", i, monitor:getName() .. status))
            print(string.format("    View: %s", monitor:getViewName()))
        end

        print("")
        print("Commands:")
        print("  [1-" .. #monitors .. "] Select monitor to cycle view")
        print("  [B] Back to main menu")
        print("")
        write("Choice: ")

        local event, key = os.pullEvent("key")

        -- Check for back
        if key == keys.b then
            return nil
        end

        -- Check for number keys
        local keyName = keys.getName(key)
        if keyName then
            local num = tonumber(keyName)
            if num and num >= 1 and num <= #monitors then
                -- Show view selection for this monitor
                local result = Menu.showViewSelect(monitors[num], availableViews)
                if result then
                    return "change_view", num, result
                end
            end
        end
    end
end

-- Show view selection for a specific monitor
function Menu.showViewSelect(monitor, availableViews)
    term.clear()
    term.setCursorPos(1, 1)

    print("=== Select View ===")
    print("")
    print("Monitor: " .. monitor:getName())
    print("Current: " .. monitor:getViewName())
    print("")

    if #availableViews == 0 then
        print("No views available.")
        print("")
        print("Press any key to go back...")
        os.pullEvent("key")
        return nil
    end

    -- Find current view index
    local currentIndex = 1
    for i, view in ipairs(availableViews) do
        if view == monitor:getViewName() then
            currentIndex = i
            break
        end
    end

    -- List views with numbers
    for i, view in ipairs(availableViews) do
        local marker = (i == currentIndex) and " <--" or ""
        print(string.format("[%d] %s%s", i, view, marker))
    end

    print("")
    print("[N] Next view  [P] Previous view  [B] Back")
    print("")
    write("Choice: ")

    local event, key = os.pullEvent("key")

    -- Check for back
    if key == keys.b then
        return nil
    end

    -- Check for next/prev
    if key == keys.n then
        local nextIndex = currentIndex + 1
        if nextIndex > #availableViews then nextIndex = 1 end
        return availableViews[nextIndex]
    elseif key == keys.p then
        local prevIndex = currentIndex - 1
        if prevIndex < 1 then prevIndex = #availableViews end
        return availableViews[prevIndex]
    end

    -- Check for number keys
    local keyName = keys.getName(key)
    if keyName then
        local num = tonumber(keyName)
        if num and num >= 1 and num <= #availableViews then
            return availableViews[num]
        end
    end

    return nil
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
