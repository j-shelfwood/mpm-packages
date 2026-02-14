-- MainMenu.lua
-- Main menu screen for shelfos-swarm pocket computer
-- Displays swarm info header with colored menu items
-- Replaces App:drawMenu() and App:run() event loop

local TermUI = mpm('shelfos-swarm/ui/TermUI')
local Core = mpm('ui/Core')

local MainMenu = {}

-- Lazy-loaded screen references (avoids circular requires)
local screens = {}
local function getScreen(name)
    if not screens[name] then
        if name == "AddZone" then
            screens[name] = mpm('shelfos-swarm/screens/AddZone')
        elseif name == "ViewZones" then
            screens[name] = mpm('shelfos-swarm/screens/ViewZones')
        elseif name == "DeleteSwarm" then
            screens[name] = mpm('shelfos-swarm/screens/DeleteSwarm')
        end
    end
    return screens[name]
end

-- Draw the main menu
function MainMenu.draw(ctx)
    local info = ctx.app.authority:getInfo()

    TermUI.clear()

    -- Title bar
    local title = info and info.name or "ShelfOS Swarm"
    TermUI.drawTitleBar(title)

    -- Swarm info section
    local y = 3
    if info then
        TermUI.drawInfoLine(y, "Fingerprint", info.fingerprint, colors.lightGray)
        y = y + 1

        local zoneColor = info.zoneCount > 0 and colors.lime or colors.orange
        TermUI.drawInfoLine(y, "Zones", info.zoneCount .. " active", zoneColor)
        y = y + 1
    end

    -- Separator
    y = y + 1
    TermUI.drawSeparator(y, colors.gray)

    -- Menu items
    y = y + 2
    TermUI.drawMenuItem(y, "A", "Add Zone")
    y = y + 1

    local zoneBadge = info and ("(" .. info.zoneCount .. ")") or nil
    TermUI.drawMenuItem(y, "Z", "View Zones", { badge = zoneBadge })
    y = y + 1

    y = y + 1
    TermUI.drawMenuItem(y, "D", "Delete Swarm", { color = colors.red })

    -- Status bar
    TermUI.drawStatusBar({{ key = "Q", label = "Quit" }})
end

-- Handle events
function MainMenu.handleEvent(ctx, event, p1, ...)
    if event == "key" then
        local keyName = keys.getName(p1)
        if not keyName then return nil end
        keyName = keyName:lower()

        if keyName == "q" then
            return "quit"
        elseif keyName == "a" then
            return { push = getScreen("AddZone") }
        elseif keyName == "z" then
            return { push = getScreen("ViewZones") }
        elseif keyName == "d" then
            return { push = getScreen("DeleteSwarm") }
        end
    end

    return nil
end

-- Called when returning to this screen from a child
function MainMenu.onResume(ctx, result)
    -- Refresh display with latest data
    MainMenu.draw(ctx)
end

return MainMenu
