-- Menu.lua
-- Menu dialogs and key handling for ShelfOS
-- Uses Controller abstraction for unified terminal/monitor support

local Controller = mpm('ui/Controller')
local Keys = mpm('utils/Keys')
local EventUtils = mpm('utils/EventUtils')

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

-- Show status dialog
-- @param config ShelfOS configuration
-- @param target Term-like object (default: term.current())
function Menu.showStatus(config, target)
    target = target or term.current()

    local lines = {
        "",
        "Zone: " .. (config.zone.name or "Unknown"),
        "Zone ID: " .. (config.zone.id or "N/A"),
        ""
    }

    -- Monitor list
    local monitors = config.monitors or {}
    table.insert(lines, "Monitors (" .. #monitors .. "):")

    for _, m in ipairs(monitors) do
        table.insert(lines, "  " .. m.peripheral .. " -> " .. m.view)
    end

    table.insert(lines, "")

    -- Network/Swarm status
    if config.network.enabled then
        -- Check for swarm peers using native rednet.lookup
        local peerCount = 0
        local peerIds = {}
        local modemOpen = false

        -- Check if rednet is available (modem must be open)
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.hasType(name, "modem") then
                if rednet.isOpen(name) then
                    modemOpen = true
                    break
                end
            end
        end

        if modemOpen then
            peerIds = {rednet.lookup("shelfos")}
            peerCount = #peerIds
        end

        -- Swarm status line
        if peerCount > 0 then
            local peerWord = peerCount == 1 and "peer" or "peers"
            table.insert(lines, "Swarm of " .. peerCount .. " " .. peerWord .. " online")
            table.insert(lines, "  IDs: " .. table.concat(peerIds, ", "))
        else
            table.insert(lines, "Swarm: No peers found")
            table.insert(lines, "  (other computers may be offline)")
        end

        table.insert(lines, "")
        table.insert(lines, "Pairing code: " .. (config.network.pairingCode or "N/A"))
        table.insert(lines, "  (use this code to add computers)")
    else
        table.insert(lines, "Network: Standalone (not in swarm)")
        table.insert(lines, "  Press [L] to create or join a swarm")
    end

    -- Local shared peripherals (shareable types)
    if config.network.enabled then
        local shareableTypes = {
            me_bridge = true, rsBridge = true, energyStorage = true,
            energy_storage = true, inventory = true, chest = true,
            fluid_storage = true, environment_detector = true,
            player_detector = true, colony_integrator = true, chat_box = true
        }
        local shared = {}
        for _, name in ipairs(peripheral.getNames()) do
            local pType = peripheral.getType(name)
            if shareableTypes[pType] then
                table.insert(shared, {name = name, type = pType})
            end
        end

        table.insert(lines, "")
        table.insert(lines, "Sharing (" .. #shared .. " local):")
        if #shared == 0 then
            table.insert(lines, "  (no shareable peripherals)")
        else
            for _, p in ipairs(shared) do
                table.insert(lines, "  " .. p.name .. " [" .. p.type .. "]")
            end
        end
    end

    -- Remote peripherals (if available)
    local ok, RemotePeripheral = pcall(mpm, 'net/RemotePeripheral')
    if ok and RemotePeripheral and RemotePeripheral.hasClient() then
        local client = RemotePeripheral.getClient()
        local remotePeriphs = {}

        -- Get remote peripherals with host info
        if client and client.remotePeripherals then
            for name, info in pairs(client.remotePeripherals) do
                local hostZone = client.hostZones[info.hostId]
                local hostName = hostZone and hostZone.zoneName or ("Computer #" .. info.hostId)
                table.insert(remotePeriphs, {
                    name = name,
                    type = info.type,
                    host = hostName
                })
            end
        end

        table.insert(lines, "")
        table.insert(lines, "Remote (" .. #remotePeriphs .. " available):")
        if #remotePeriphs == 0 then
            table.insert(lines, "  (none discovered yet)")
        else
            for _, p in ipairs(remotePeriphs) do
                table.insert(lines, "  " .. p.name .. " [" .. p.type .. "]")
                table.insert(lines, "    from: " .. p.host)
            end
        end
    elseif config.network.enabled then
        table.insert(lines, "")
        table.insert(lines, "Remote: (client not initialized)")
    end

    Controller.showInfo(target, "ShelfOS Status", lines)
end

-- Show monitors overview dialog
-- Returns: action, monitorIndex, newView (e.g., "change_view", 1, "StorageCapacityDisplay")
-- @param monitors Array of Monitor instances
-- @param availableViews Array of view names
-- @param target Term-like object (default: term.current())
function Menu.showMonitors(monitors, availableViews, target)
    target = target or term.current()

    if #monitors == 0 then
        Controller.showInfo(target, "Monitors", {
            "",
            "No monitors connected.",
            "",
            "Connect monitors and restart ShelfOS."
        })
        return nil
    end

    -- Build options list with monitor info
    local options = {}
    for i, monitor in ipairs(monitors) do
        local status = monitor:isConnected() and "" or " (disconnected)"
        local viewName = monitor:getViewName() or "None"

        table.insert(options, {
            value = i,
            label = monitor:getName() .. status,
            sublabel = "View: " .. viewName
        })
    end

    -- Custom format function to show both name and view
    local function formatMonitor(opt)
        return opt.label .. " [" .. (opt.sublabel or "") .. "]"
    end

    local selectedIndex = Controller.selectFromList(target, "Monitors", options, {
        showNumbers = true,
        showBack = true,
        formatFn = formatMonitor
    })

    if selectedIndex == nil then
        return nil
    end

    -- Show view selection for selected monitor
    local result = Menu.showViewSelect(monitors[selectedIndex], availableViews, target)

    if result then
        return "change_view", selectedIndex, result
    end

    return nil
end

-- Show view selection for a specific monitor
-- @param monitor Monitor instance
-- @param availableViews Array of view names
-- @param target Term-like object (default: term.current())
-- @return Selected view name or nil if cancelled
function Menu.showViewSelect(monitor, availableViews, target)
    target = target or term.current()

    if #availableViews == 0 then
        Controller.showInfo(target, "Select View", {
            "",
            "No views available.",
            "",
            "Check that view modules are installed."
        })
        return nil
    end

    -- Find current view index
    local currentView = monitor:getViewName()
    local currentIndex = 1

    for i, view in ipairs(availableViews) do
        if view == currentView then
            currentIndex = i
            break
        end
    end

    -- Build options with current marker
    local options = {}
    for i, view in ipairs(availableViews) do
        local marker = (view == currentView) and " *" or ""
        table.insert(options, {
            value = view,
            label = view .. marker
        })
    end

    -- Define shortcuts for next/previous navigation
    local shortcuts = {
        n = function()
            local nextIndex = currentIndex + 1
            if nextIndex > #availableViews then nextIndex = 1 end
            return availableViews[nextIndex]
        end,
        p = function()
            local prevIndex = currentIndex - 1
            if prevIndex < 1 then prevIndex = #availableViews end
            return availableViews[prevIndex]
        end
    }

    -- Custom event loop that handles N/P shortcuts
    local width, height = target.getSize()
    local isMonitor, monitorName = Controller.isMonitor(target)
    local scrollOffset = 0

    -- Format function
    local function formatView(opt)
        return opt.label
    end

    -- Get value
    local function getValue(opt)
        if type(opt) == "table" then
            return opt.value
        end
        return opt
    end

    -- Calculate layout
    local function getLayout()
        local titleHeight = 3  -- Title + monitor name + blank
        local footerHeight = 2
        local startY = titleHeight + 1
        local maxVisible = height - startY - footerHeight
        return startY, math.max(1, maxVisible)
    end

    -- Initial scroll
    local startY, maxVisible = getLayout()
    if currentIndex > maxVisible then
        scrollOffset = currentIndex - maxVisible
    end

    -- Render function
    local function render()
        Controller.clear(target)
        Controller.drawTitle(target, "Select View")

        -- Monitor name
        target.setTextColor(colors.lightGray)
        target.setCursorPos(2, 3)
        local monName = monitor:getName()
        if #monName > width - 4 then
            monName = monName:sub(1, width - 7) .. "..."
        end
        target.write("Monitor: " .. monName)

        local startY, maxVisible = getLayout()

        -- Options list
        local visibleCount = math.min(maxVisible, #options - scrollOffset)

        for i = 1, visibleCount do
            local optIndex = i + scrollOffset
            local opt = options[optIndex]

            if opt then
                local y = startY + i - 1
                local label = formatView(opt)
                local value = getValue(opt)
                local isSelected = value == currentView

                -- Number prefix
                local prefix = ""
                if optIndex <= 9 then
                    prefix = "[" .. optIndex .. "] "
                else
                    prefix = "    "
                end

                -- Truncate if needed
                local maxLen = width - #prefix - 2
                if #label > maxLen then
                    label = label:sub(1, maxLen - 3) .. "..."
                end

                if isSelected then
                    target.setBackgroundColor(colors.gray)
                    target.setTextColor(colors.white)
                    target.setCursorPos(1, y)
                    target.write(string.rep(" ", width))
                    target.setCursorPos(2, y)
                    target.write(prefix .. label)
                else
                    target.setBackgroundColor(colors.black)
                    target.setTextColor(colors.lightGray)
                    target.setCursorPos(2, y)
                    target.write(prefix .. label)
                end
            end
        end

        -- Scroll indicators
        target.setBackgroundColor(colors.black)
        target.setTextColor(colors.gray)

        if scrollOffset > 0 then
            target.setCursorPos(width, startY)
            target.write("^")
        end

        if scrollOffset + maxVisible < #options then
            target.setCursorPos(width, startY + maxVisible - 1)
            target.write("v")
        end

        -- Footer with shortcuts
        target.setTextColor(colors.yellow)
        target.setCursorPos(2, height - 1)
        target.write("[N] Next  [P] Prev  [B] Back")

        target.setBackgroundColor(colors.black)
        target.setTextColor(colors.white)
    end

    -- Event loop
    while true do
        render()

        local event, p1, p2, p3 = os.pullEvent()

        if event == "key" then
            local keyName = keys.getName(p1)

            if keyName then
                keyName = keyName:lower()

                -- Back
                if keyName == "b" then
                    return nil
                end

                -- Next/Previous
                if keyName == "n" then
                    local nextIndex = currentIndex + 1
                    if nextIndex > #availableViews then nextIndex = 1 end
                    return availableViews[nextIndex]
                elseif keyName == "p" then
                    local prevIndex = currentIndex - 1
                    if prevIndex < 1 then prevIndex = #availableViews end
                    return availableViews[prevIndex]
                end

                -- Number selection (1-9)
                local num = Keys.getNumber(keyName)
                if num and num >= 1 and num <= #availableViews then
                    return availableViews[num]
                end

                -- Arrow keys for scrolling
                if keyName == "up" and scrollOffset > 0 then
                    scrollOffset = scrollOffset - 1
                elseif keyName == "down" and scrollOffset + maxVisible < #options then
                    scrollOffset = scrollOffset + 1
                end
            end

        elseif event == "monitor_touch" and p1 == monitorName then
            local startY, maxVisible = getLayout()

            -- Back (bottom area)
            if p3 >= height - 1 then
                return nil
            end

            -- Scroll indicators
            if p2 == width then
                if p3 == startY and scrollOffset > 0 then
                    scrollOffset = scrollOffset - 1
                elseif p3 == startY + maxVisible - 1 and scrollOffset + maxVisible < #options then
                    scrollOffset = scrollOffset + 1
                end
            else
                -- Option selection
                if p3 >= startY and p3 < startY + maxVisible then
                    local optIndex = (p3 - startY + 1) + scrollOffset
                    if optIndex >= 1 and optIndex <= #availableViews then
                        return availableViews[optIndex]
                    end
                end
            end
        end
    end
end

-- Show reset confirmation dialog
-- @param target Term-like object (default: term.current())
-- @return boolean confirmed
function Menu.showReset(target)
    target = target or term.current()

    return Controller.showConfirm(target, "Reset ShelfOS",
        "Delete configuration and auto-configure on restart?",
        { confirmKey = "y", cancelKey = "n" }
    )
end

-- Show link menu dialog
-- @param config ShelfOS configuration
-- @param target Term-like object (default: term.current())
-- @return action string or nil, optional code string
function Menu.showLink(config, target)
    target = target or term.current()

    local options = {}
    local isConnected = config.network.enabled

    if isConnected then
        options = {
            { value = "show_code", label = "Show pairing code" },
            { value = "host", label = "Host pairing session" },
            { value = "pocket_accept", label = "Accept from pocket" },
            { value = "disconnect", label = "Disconnect from swarm" },
            { value = "back", label = "Back" }
        }
    else
        options = {
            { value = "show_code", label = "Show pairing code" },
            { value = "host", label = "Host pairing session" },
            { value = "pocket_accept", label = "Accept from pocket" },
            { value = "join", label = "Join existing swarm" },
            { value = "back", label = "Back" }
        }
    end

    -- Build title with status
    local title = "Network Link"

    local width, height = target.getSize()
    local isMonitor, monitorName = Controller.isMonitor(target)

    Controller.clear(target)
    Controller.drawTitle(target, title)

    -- Status line with peer count
    local startY = 5
    if isConnected then
        -- Check for swarm peers
        local peerCount = 0
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.hasType(name, "modem") and rednet.isOpen(name) then
                local peerIds = {rednet.lookup("shelfos")}
                peerCount = #peerIds
                break
            end
        end

        target.setTextColor(colors.lime)
        target.setCursorPos(2, 3)
        if peerCount > 0 then
            local peerWord = peerCount == 1 and "peer" or "peers"
            target.write("Swarm of " .. peerCount .. " " .. peerWord .. " online")
        else
            target.write("Swarm: Connected (no peers found)")
        end

        target.setTextColor(colors.yellow)
        target.setCursorPos(2, 4)
        target.write("Code: " .. (config.network.pairingCode or "N/A"))
        startY = 6
    else
        target.setTextColor(colors.orange)
        target.setCursorPos(2, 3)
        target.write("Status: Standalone")

        target.setTextColor(colors.gray)
        target.setCursorPos(2, 4)
        target.write("Code: " .. (config.network.pairingCode or "N/A"))
        startY = 6
    end

    -- Options
    for i, opt in ipairs(options) do
        local y = startY + i - 1
        if y < height - 1 then
            target.setTextColor(colors.lightGray)
            target.setCursorPos(2, y)
            target.write("[" .. i .. "] " .. opt.label)
        end
    end

    target.setTextColor(colors.white)

    -- Wait for selection
    while true do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "key" then
            local keyName = keys.getName(p1)
            if keyName then
                keyName = keyName:lower()
                local num = Keys.getNumber(keyName)
                if num and num >= 1 and num <= #options then
                    local selected = options[num].value

                    if selected == "back" then
                        return nil
                    elseif selected == "show_code" then
                        Controller.showInfo(target, "Pairing Code", {
                            "",
                            "Code: " .. (config.network.pairingCode or "N/A"),
                            "",
                            "Share this code with other computers",
                            "to join this swarm."
                        })
                        return nil
                    elseif selected == "host" then
                        return "link_host"
                    elseif selected == "pocket_accept" then
                        return "link_pocket_accept"
                    elseif selected == "disconnect" then
                        return "link_disconnect"
                    elseif selected == "join" then
                        -- Need to get pairing code input
                        target.setCursorPos(2, height - 2)
                        target.setTextColor(colors.white)
                        write("Enter pairing code: ")

                        local code = read()

                        if code and #code >= 8 then
                            return "link_join", code
                        else
                            target.setCursorPos(2, height - 1)
                            target.setTextColor(colors.red)
                            target.write("Invalid code (min 8 chars)")
                            EventUtils.sleep(1)
                            return nil
                        end
                    end
                end
            end

        elseif event == "monitor_touch" and p1 == monitorName then
            -- Check option touches
            for i, opt in ipairs(options) do
                local y = startY + i - 1
                if p3 == y then
                    local selected = opt.value

                    if selected == "back" then
                        return nil
                    elseif selected == "show_code" then
                        Controller.showInfo(target, "Pairing Code", {
                            "",
                            "Code: " .. (config.network.pairingCode or "N/A"),
                            "",
                            "Share this code with other computers."
                        })
                        return nil
                    elseif selected == "host" then
                        return "link_host"
                    elseif selected == "pocket_accept" then
                        return "link_pocket_accept"
                    elseif selected == "disconnect" then
                        return "link_disconnect"
                    elseif selected == "join" then
                        -- Can't input on monitor
                        Controller.showInfo(target, "Join Swarm", {
                            "",
                            "Text input required.",
                            "Use terminal keyboard to enter code."
                        })
                        return nil
                    end
                end
            end
        end
    end
end

return Menu
