-- CreateSwarm.lua
-- Swarm creation screen for shelfos-swarm pocket computer
-- Multi-step: name input -> creation -> success display
-- Extracted from App:createSwarm()

local TermUI = mpm('ui/TermUI')

local CreateSwarm = {}

-- State for the creation flow
local state = {
    phase = "input",  -- "input", "creating", "success", "error"
    name = nil,
    info = nil,
    errorMsg = nil
}

function CreateSwarm.onEnter(ctx, args)
    state.phase = "input"
    state.name = nil
    state.info = nil
    state.errorMsg = nil
end

function CreateSwarm.draw(ctx)
    TermUI.clear()
    TermUI.drawTitleBar("Create New Swarm")

    if state.phase == "input" then
        CreateSwarm.drawInput(ctx)
    elseif state.phase == "creating" then
        CreateSwarm.drawCreating(ctx)
    elseif state.phase == "success" then
        CreateSwarm.drawSuccess(ctx)
    elseif state.phase == "error" then
        CreateSwarm.drawError(ctx)
    end
end

function CreateSwarm.drawInput(ctx)
    local y = 4
    TermUI.drawText(2, y, "Enter a name for your swarm:", colors.lightGray)
    y = y + 1
    TermUI.drawText(2, y, "(leave blank for default)", colors.gray)
    y = y + 2

    -- Prompt
    term.setCursorPos(2, y)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow)
    term.write("> ")
    term.setTextColor(colors.white)

    -- read() will handle input
    local input = read()
    if not input or #input == 0 then
        input = "My Swarm"
    end

    state.name = input

    -- Transition to creating
    state.phase = "creating"
    CreateSwarm.draw(ctx)

    -- Actually create the swarm
    local ok, swarmId = ctx.app.authority:createSwarm(state.name)
    if ok then
        state.info = ctx.app.authority:getInfo()
        state.phase = "success"

        -- Initialize networking
        ctx.app:initNetwork()
    else
        state.errorMsg = "Failed to create swarm"
        state.phase = "error"
    end

    CreateSwarm.draw(ctx)
end

function CreateSwarm.drawCreating(ctx)
    local y = math.floor(ctx.height / 2) - 1
    TermUI.drawSpinner(y, "Creating swarm...", 0)
    TermUI.drawText(2, y + 1, state.name or "", colors.lightGray)
end

function CreateSwarm.drawSuccess(ctx)
    local y = 4

    TermUI.drawText(2, y, "Swarm created!", colors.lime)
    y = y + 2

    if state.info then
        TermUI.drawInfoLine(y, "Name", state.info.name, colors.white)
        y = y + 1
        TermUI.drawInfoLine(y, "ID", state.info.id, colors.lightGray)
        y = y + 1
        TermUI.drawInfoLine(y, "Fingerprint", state.info.fingerprint, colors.yellow)
        y = y + 2

        TermUI.drawWrapped(y, "This fingerprint identifies your swarm. Computers will display it after pairing.", colors.lightGray, 2, 3)
    end

    TermUI.drawStatusBar("Press any key to continue...")
end

function CreateSwarm.drawError(ctx)
    local y = math.floor(ctx.height / 2) - 1
    TermUI.drawText(2, y, "Error", colors.red)
    TermUI.drawText(2, y + 1, state.errorMsg or "Unknown error", colors.orange)
    y = y + 3
    TermUI.drawText(2, y, "Press any key to go back.", colors.lightGray)

    TermUI.drawStatusBar("Press any key...")
end

function CreateSwarm.handleEvent(ctx, event, p1, ...)
    if event == "key" then
        if state.phase == "success" then
            -- Done: replace with MainMenu
            local MainMenu = mpm('shelfos-swarm/screens/MainMenu')
            return { replace = MainMenu }
        elseif state.phase == "error" then
            return "pop"
        end
        -- "input" phase: read() handles key events internally
        -- "creating" phase: no input expected
    end

    return nil
end

return CreateSwarm
