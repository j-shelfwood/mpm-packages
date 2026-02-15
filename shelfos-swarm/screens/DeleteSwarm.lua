-- DeleteSwarm.lua
-- Swarm deletion confirmation screen for shelfos-swarm pocket computer
-- Red-themed danger confirmation with styled layout
-- Handles complete swarm teardown with Y/N confirmation

local TermUI = mpm('ui/TermUI')
local Paths = mpm('shelfos-swarm/core/Paths')

local DeleteSwarm = {}

function DeleteSwarm.draw(ctx)
    local info = ctx.app.authority:getInfo()

    TermUI.clear()

    -- Red title bar for danger
    TermUI.drawTitleBar("DELETE SWARM", colors.red)

    local y = 3

    -- Warning
    TermUI.drawText(2, y, "WARNING", colors.orange)
    y = y + 2

    -- What will be deleted
    TermUI.drawText(2, y, "This will delete:", colors.white)
    y = y + 1

    local swarmName = info and info.name or "Unknown"
    local computerCount = info and info.computerCount or 0

    term.setCursorPos(2, y)
    term.setTextColor(colors.lightGray)
    term.write("  * Swarm: ")
    term.setTextColor(colors.white)
    term.write(swarmName)
    y = y + 1

    term.setCursorPos(2, y)
    term.setTextColor(colors.lightGray)
    term.write("  * " .. computerCount .. " registered computer(s)")
    y = y + 1

    term.setCursorPos(2, y)
    term.setTextColor(colors.lightGray)
    term.write("  * All credentials")
    y = y + 2

    TermUI.drawWrapped(y, "Computers will need to re-pair after deletion.", colors.gray, 2, 2)

    -- Footer with Y/N
    local w, h = TermUI.getSize()
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.write(string.rep(" ", w))

    -- [Y] Delete in red
    term.setCursorPos(2, h)
    term.setTextColor(colors.red)
    term.write("[Y]")
    term.setTextColor(colors.white)
    term.write(" Delete  ")

    -- [N] Cancel in green
    term.setTextColor(colors.lime)
    term.write("[N]")
    term.setTextColor(colors.white)
    term.write(" Cancel")

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

function DeleteSwarm.handleEvent(ctx, event, p1, ...)
    if event == "key" then
        local keyName = keys.getName(p1)
        if not keyName then return nil end
        keyName = keyName:lower()

        if keyName == "y" then
            -- Close network
            rednet.unhost("shelfos_swarm")

            -- Delete swarm
            ctx.app.authority:deleteSwarm()
            Paths.deleteAll()

            -- Show deletion message
            TermUI.clear()
            TermUI.drawTitleBar("SWARM DELETED", colors.red)

            local y = math.floor(ctx.height / 2)
            TermUI.drawCentered(y, "Swarm deleted", colors.orange)
            TermUI.drawCentered(y + 1, "Rebooting...", colors.lightGray)

            sleep(2)
            os.reboot()
            -- Never returns

        elseif keyName == "n" or keyName == "b" or keyName == "backspace" then
            return "pop"
        end
    end

    return nil
end

return DeleteSwarm
