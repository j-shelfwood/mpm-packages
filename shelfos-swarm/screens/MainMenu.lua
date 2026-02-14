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
        if name == "AddComputer" then
            screens[name] = mpm('shelfos-swarm/screens/AddComputer')
        elseif name == "ViewComputers" then
            screens[name] = mpm('shelfos-swarm/screens/ViewComputers')
        elseif name == "DeleteSwarm" then
            screens[name] = mpm('shelfos-swarm/screens/DeleteSwarm')
        elseif name == "RebootSwarm" then
            screens[name] = mpm('shelfos-swarm/screens/RebootSwarm')
        elseif name == "ViewPeripherals" then
            screens[name] = mpm('shelfos-swarm/screens/ViewPeripherals')
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

        local computerColor = info.computerCount > 0 and colors.lime or colors.orange
        TermUI.drawInfoLine(y, "Computers", info.computerCount .. " active", computerColor)
        y = y + 1
    end

    -- Separator
    y = y + 1
    TermUI.drawSeparator(y, colors.gray)

    -- Menu items
    y = y + 2
    TermUI.drawMenuItem(y, "A", "Add Computer")
    y = y + 1

    local computerBadge = info and ("(" .. info.computerCount .. ")") or nil
    TermUI.drawMenuItem(y, "C", "View Computers", { badge = computerBadge })
    y = y + 1

    TermUI.drawMenuItem(y, "P", "Peripherals")
    y = y + 1

    y = y + 1
    TermUI.drawMenuItem(y, "R", "Reboot Swarm", { color = colors.orange })
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
            return { push = getScreen("AddComputer") }
        elseif keyName == "c" then
            return { push = getScreen("ViewComputers") }
        elseif keyName == "p" then
            return { push = getScreen("ViewPeripherals") }
        elseif keyName == "r" then
            return { push = getScreen("RebootSwarm") }
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
