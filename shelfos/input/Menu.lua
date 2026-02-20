-- Menu.lua
-- Menu dialogs and key handling for ShelfOS
-- Uses Controller abstraction for unified terminal/monitor support
--
-- Split modules:
--   MenuStatus.lua - Status dialog rendering

local Controller = mpm('ui/Controller')
local ListSelector = mpm('ui/ListSelector')
local EventLoop = mpm('ui/EventLoop')
local Keys = mpm('utils/Keys')
local MenuStatus = mpm('shelfos/input/MenuStatus')

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

-- Show status dialog (delegates to MenuStatus)
-- @param config ShelfOS configuration
-- @param target Term-like object (default: term.current())
function Menu.showStatus(config, target)
    MenuStatus.show(config, target)
end

-- Show monitors overview dialog
-- Returns: action, monitorIndex, newView (e.g., "change_view", 1, "StorageGraph")
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
            "Connect a monitor, then open",
            "this menu again to configure views."
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

    local currentView = monitor:getViewName()
    local currentIndex = 1
    local options = {}

    for i, view in ipairs(availableViews) do
        if view == currentView then
            currentIndex = i
        end
        local marker = (view == currentView) and " *" or ""
        table.insert(options, { value = view, label = view .. marker })
    end

    local shortcuts = {
        n = availableViews[(currentIndex % #availableViews) + 1],
        p = availableViews[((currentIndex - 2 + #availableViews) % #availableViews) + 1]
    }

    return ListSelector.show(target, "Select View", options, {
        selected = currentView,
        showNumbers = true,
        showBack = true,
        formatFn = function(opt) return opt.label end,
        shortcuts = shortcuts
    })
end

-- Show reset confirmation dialog
-- @param target Term-like object (default: term.current())
-- @return boolean confirmed
function Menu.showReset(target)
    target = target or term.current()

    return Controller.showConfirm(target, "Reset ShelfOS",
        "Delete configuration and reboot? Next boot defaults monitors to Clock.",
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
    -- Check if computer is in swarm (has secret)
    local isInSwarm = config.network and config.network.secret ~= nil

    if isInSwarm then
        -- IN SWARM: Can re-pair with pocket or disconnect
        options = {
            { value = "pocket_accept", label = "Re-pair with pocket" },
            { value = "disconnect", label = "Leave swarm" },
            { value = "back", label = "Back" }
        }
    else
        -- NOT IN SWARM: Can only accept from pocket
        options = {
            { value = "pocket_accept", label = "Accept from pocket" },
            { value = "back", label = "Back" }
        }
    end

    -- Build title with status
    local title = "Network Link"

    local isMonitor, monitorName = Controller.isMonitor(target)

    local function render()
        local width, height = target.getSize()
        local startY = 5

        Controller.clear(target)
        Controller.drawTitle(target, title)

        -- Status line with peer count
        if isInSwarm then
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
                target.write("In swarm: " .. peerCount .. " " .. peerWord .. " online")
            else
                target.write("In swarm (no peers found)")
            end
            startY = 5
        else
            target.setTextColor(colors.orange)
            target.setCursorPos(2, 3)
            target.write("Not in swarm")

            target.setTextColor(colors.gray)
            target.setCursorPos(2, 4)
            target.write("Pair with pocket to join")
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
        return startY, height
    end

    -- Wait for selection
    while true do
        local startY, height = render()
        local kind, p1, p2 = EventLoop.waitForTouchOrKey(monitorName)

        if kind == "key" then
            local keyName = keys.getName(p1)
            if keyName then
                keyName = keyName:lower()
                local num = Keys.getNumber(keyName)
                if num and num >= 1 and num <= #options then
                    local selected = options[num].value

                    if selected == "back" then
                        return nil
                    elseif selected == "pocket_accept" then
                        return "link_pocket_accept"
                    elseif selected == "disconnect" then
                        return "link_disconnect"
                    end
                end
            end

        elseif kind == "touch" then
            -- Check option touches
            for i, opt in ipairs(options) do
                local y = startY + i - 1
                if p2 == y then
                    local selected = opt.value

                    if selected == "back" then
                        return nil
                    elseif selected == "pocket_accept" then
                        return "link_pocket_accept"
                    elseif selected == "disconnect" then
                        return "link_disconnect"
                    end
                end
            end
        elseif kind == "resize" then
            -- Re-render on next loop iteration.
        elseif kind == "detach" then
            return nil
        end
    end
end

return Menu
