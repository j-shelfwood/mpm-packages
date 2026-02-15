-- RebootSwarm.lua
-- Remote reboot confirmation screen for shelfos-swarm pocket computer
-- Orange-themed confirmation with styled layout
-- Broadcasts REBOOT command to all swarm computers via authenticated channel

local TermUI = mpm('ui/TermUI')
local Protocol = mpm('net/Protocol')

local RebootSwarm = {}

-- Internal state
local state = {
    phase = "confirm",  -- "confirm", "sent", "error"
    errorMsg = nil
}

function RebootSwarm.onEnter(ctx, args)
    state.phase = "confirm"
    state.errorMsg = nil
end

function RebootSwarm.draw(ctx)
    TermUI.clear()

    if state.phase == "confirm" then
        RebootSwarm.drawConfirm(ctx)
    elseif state.phase == "sent" then
        RebootSwarm.drawSent(ctx)
    elseif state.phase == "error" then
        RebootSwarm.drawError(ctx)
    end
end

function RebootSwarm.drawConfirm(ctx)
    local info = ctx.app.authority:getInfo()

    -- Orange title bar for warning
    TermUI.drawTitleBar("REBOOT SWARM", colors.orange)

    local y = 3

    TermUI.drawText(2, y, "WARNING", colors.orange)
    y = y + 2

    local swarmName = info and info.name or "Unknown"
    local computerCount = info and info.computerCount or 0

    TermUI.drawText(2, y, "This will reboot:", colors.white)
    y = y + 1

    term.setCursorPos(2, y)
    term.setTextColor(colors.lightGray)
    term.write("  * Swarm: ")
    term.setTextColor(colors.white)
    term.write(swarmName)
    y = y + 1

    term.setCursorPos(2, y)
    term.setTextColor(colors.lightGray)
    term.write("  * " .. computerCount .. " registered computer(s)")
    y = y + 2

    TermUI.drawWrapped(y, "All swarm computers will restart immediately.", colors.gray, 2, 2)

    -- Footer with Y/N
    local w, h = TermUI.getSize()
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.write(string.rep(" ", w))

    -- [Y] Reboot in orange
    term.setCursorPos(2, h)
    term.setTextColor(colors.orange)
    term.write("[Y]")
    term.setTextColor(colors.white)
    term.write(" Reboot  ")

    -- [N] Cancel in green
    term.setTextColor(colors.lime)
    term.write("[N]")
    term.setTextColor(colors.white)
    term.write(" Cancel")

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

function RebootSwarm.drawSent(ctx)
    TermUI.drawTitleBar("REBOOT SWARM", colors.orange)

    local y = math.floor(ctx.height / 2) - 1
    TermUI.drawCentered(y, "Reboot signal sent", colors.lime)
    TermUI.drawCentered(y + 1, "Computers are restarting...", colors.lightGray)

    TermUI.drawStatusBar("Returning to menu...")
end

function RebootSwarm.drawError(ctx)
    TermUI.drawTitleBar("REBOOT SWARM", colors.orange)

    local y = math.floor(ctx.height / 2) - 1
    TermUI.drawText(2, y, "Error", colors.red)
    y = y + 1
    TermUI.drawWrapped(y, state.errorMsg or "Unknown error", colors.orange, 2, 3)

    TermUI.drawStatusBar("Press any key to go back...")
end

function RebootSwarm.handleEvent(ctx, event, p1, ...)
    if event == "key" then
        local keyName = keys.getName(p1)
        if not keyName then return nil end
        keyName = keyName:lower()

        if state.phase == "confirm" then
            if keyName == "y" then
                -- Check channel exists
                if not ctx.app.channel then
                    state.phase = "error"
                    state.errorMsg = "No network channel. Restart app."
                    RebootSwarm.draw(ctx)
                    return nil
                end

                -- Broadcast reboot command via authenticated channel
                local rebootMsg = Protocol.createReboot()
                local ok, err = pcall(function()
                    ctx.app.channel:broadcast(rebootMsg)
                end)

                if ok then
                    state.phase = "sent"
                    RebootSwarm.draw(ctx)

                    -- Auto-return after 2 seconds
                    sleep(2)
                    return "pop"
                else
                    state.phase = "error"
                    state.errorMsg = "Broadcast failed: " .. tostring(err)
                    RebootSwarm.draw(ctx)
                    return nil
                end

            elseif keyName == "n" or keyName == "b" or keyName == "backspace" then
                return "pop"
            end

        elseif state.phase == "sent" then
            return "pop"

        elseif state.phase == "error" then
            return "pop"
        end
    end

    return nil
end

return RebootSwarm
