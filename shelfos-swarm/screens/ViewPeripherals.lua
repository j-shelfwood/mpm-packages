-- ViewPeripherals.lua
-- Peripheral discovery viewer for shelfos-swarm pocket computer
-- Two-phase screen: computer discovery, then peripheral detail view
-- Uses authenticated Channel to broadcast PERIPH_DISCOVER and collect responses

local TermUI = mpm('ui/TermUI')
local Protocol = mpm('net/Protocol')
local Core = mpm('ui/Core')
local Keys = mpm('utils/Keys')

local ViewPeripherals = {}

-- Internal state
local state = {
    phase = "discovering",  -- "discovering", "list", "detail", "error"
    computers = {},         -- { computerId, computerName, peripherals[], senderId }
    selectedIdx = nil,
    spinnerFrame = 0,
    discoveryTimer = nil,
    errorMsg = nil
}

local DISCOVERY_DURATION = 3000  -- 3 seconds to collect responses

function ViewPeripherals.onEnter(ctx, args)
    state.phase = "discovering"
    state.computers = {}
    state.selectedIdx = nil
    state.spinnerFrame = 0
    state.errorMsg = nil

    -- Check channel exists
    if not ctx.app.channel then
        state.phase = "error"
        state.errorMsg = "No network channel. Restart app."
        return
    end

    -- Broadcast peripheral discovery request
    local discoverMsg = Protocol.createPeriphDiscover()
    local ok, err = pcall(function()
        ctx.app.channel:broadcast(discoverMsg)
    end)

    if not ok then
        state.phase = "error"
        state.errorMsg = "Discovery failed: " .. tostring(err)
        return
    end

    -- Start discovery timer
    state.discoveryTimer = os.epoch("utc") + DISCOVERY_DURATION
    os.startTimer(0.5)  -- Start polling
end

function ViewPeripherals.draw(ctx)
    TermUI.clear()

    if state.phase == "discovering" then
        ViewPeripherals.drawDiscovering(ctx)
    elseif state.phase == "list" then
        ViewPeripherals.drawList(ctx)
    elseif state.phase == "detail" then
        ViewPeripherals.drawDetail(ctx)
    elseif state.phase == "error" then
        ViewPeripherals.drawError(ctx)
    end
end

function ViewPeripherals.drawDiscovering(ctx)
    TermUI.drawTitleBar("Peripherals")

    local y = 3
    TermUI.drawSpinner(y, "Discovering...", state.spinnerFrame)
    y = y + 2

    local count = #state.computers
    if count > 0 then
        TermUI.drawText(2, y, "Found: " .. count .. " computer(s)", colors.lime)
        y = y + 1

        for _, comp in ipairs(state.computers) do
            if y < ctx.height - 2 then
                local pCount = #(comp.peripherals or {})
                TermUI.drawText(4, y, comp.computerName .. " (" .. pCount .. ")", colors.lightGray)
                y = y + 1
            end
        end
    else
        TermUI.drawText(2, y, "Found: 0 computers", colors.lightGray)
    end

    TermUI.drawStatusBar({{ key = "B", label = "Back" }})
end

function ViewPeripherals.drawList(ctx)
    TermUI.drawTitleBar("Swarm Peripherals")

    local y = 3

    if #state.computers == 0 then
        TermUI.drawText(2, y, "No computers responded.", colors.lightGray)
        y = y + 2
        TermUI.drawText(2, y, "Ensure computers are running", colors.gray)
        y = y + 1
        TermUI.drawText(2, y, "ShelfOS with peripherals.", colors.gray)
    else
        for i, comp in ipairs(state.computers) do
            if i <= 9 and y < ctx.height - 2 then
                local pCount = #(comp.peripherals or {})

                -- Number key + computer name
                term.setCursorPos(2, y)
                term.setTextColor(colors.yellow)
                term.write("[" .. i .. "]")
                term.setTextColor(colors.lime)
                term.write(" " .. Core.truncate(comp.computerName, ctx.width - 10))

                -- Peripheral count badge
                term.setTextColor(colors.lightGray)
                term.write(" (" .. pCount .. ")")
                y = y + 1
            end
        end
    end

    TermUI.drawStatusBar({{ key = "B", label = "Back" }})
end

function ViewPeripherals.drawDetail(ctx)
    local comp = state.computers[state.selectedIdx]
    if not comp then
        state.phase = "list"
        ViewPeripherals.draw(ctx)
        return
    end

    TermUI.drawTitleBar(Core.truncate(comp.computerName, ctx.width - 2))

    local y = 3
    TermUI.drawText(2, y, "Computer #" .. (comp.senderId or "?"), colors.lightGray)
    y = y + 2

    local peripherals = comp.peripherals or {}

    if #peripherals == 0 then
        TermUI.drawText(2, y, "No peripherals shared.", colors.lightGray)
    else
        for _, p in ipairs(peripherals) do
            if y < ctx.height - 2 then
                -- Peripheral type in brackets
                term.setCursorPos(2, y)
                term.setTextColor(colors.yellow)
                term.write("[" .. (p.type or "?") .. "]")
                y = y + 1

                -- Peripheral name
                term.setCursorPos(4, y)
                term.setTextColor(colors.lightGray)
                term.write(p.name or "unknown")
                y = y + 1
            end
        end
    end

    term.setTextColor(colors.white)
    TermUI.drawStatusBar({{ key = "B", label = "Back" }})
end

function ViewPeripherals.drawError(ctx)
    TermUI.drawTitleBar("Peripherals")

    local y = math.floor(ctx.height / 2) - 1
    TermUI.drawText(2, y, "Error", colors.red)
    y = y + 1
    TermUI.drawWrapped(y, state.errorMsg or "Unknown error", colors.orange, 2, 3)

    TermUI.drawStatusBar("Press any key to go back...")
end

function ViewPeripherals.handleEvent(ctx, event, p1, p2, p3)
    if state.phase == "discovering" then
        return ViewPeripherals.handleDiscovering(ctx, event, p1, p2, p3)
    elseif state.phase == "list" then
        return ViewPeripherals.handleList(ctx, event, p1, p2, p3)
    elseif state.phase == "detail" then
        return ViewPeripherals.handleDetail(ctx, event, p1, p2, p3)
    elseif state.phase == "error" then
        if event == "key" then
            return "pop"
        end
    end

    return nil
end

function ViewPeripherals.handleDiscovering(ctx, event, p1, p2, p3)
    if event == "key" then
        local keyName = keys.getName(p1)
        if keyName and keyName:lower() == "b" then
            return "pop"
        end

    elseif event == "timer" then
        state.spinnerFrame = state.spinnerFrame + 1

        -- Poll channel for PERIPH_ANNOUNCE responses
        if ctx.app.channel then
            -- Try to receive any pending messages
            local senderId, msg = ctx.app.channel:receive(0)
            while senderId and msg do
                if msg.type == Protocol.MessageType.PERIPH_ANNOUNCE or
                   msg.type == Protocol.MessageType.PERIPH_LIST then
                    local data = msg.data or {}
                    local computerId = data.computerId or ("computer_" .. senderId)
                    local computerName = data.computerName or ("Computer " .. senderId)
                    local peripherals = data.peripherals or {}

                    -- Check if already in list
                    local found = false
                    for _, c in ipairs(state.computers) do
                        if c.senderId == senderId then
                            found = true
                            c.peripherals = peripherals
                            break
                        end
                    end

                    if not found then
                        table.insert(state.computers, {
                            computerId = computerId,
                            computerName = computerName,
                            peripherals = peripherals,
                            senderId = senderId
                        })
                    end
                end

                -- Try next message
                senderId, msg = ctx.app.channel:receive(0)
            end
        end

        -- Check if discovery period is over
        if os.epoch("utc") >= state.discoveryTimer then
            state.phase = "list"
            ViewPeripherals.draw(ctx)
            return nil
        end

        ViewPeripherals.draw(ctx)
        os.startTimer(0.5)
    end

    return nil
end

function ViewPeripherals.handleList(ctx, event, p1, p2, p3)
    if event == "key" then
        local keyName = keys.getName(p1)
        if not keyName then return nil end
        keyName = keyName:lower()

        if keyName == "b" or keyName == "backspace" then
            return "pop"
        end

        -- Number selection for detail view
        local num = Keys.getNumber(keyName)
        if num and num >= 1 and num <= #state.computers then
            state.selectedIdx = num
            state.phase = "detail"
            ViewPeripherals.draw(ctx)
            return nil
        end
    end

    return nil
end

function ViewPeripherals.handleDetail(ctx, event, p1, p2, p3)
    if event == "key" then
        local keyName = keys.getName(p1)
        if not keyName then return nil end
        keyName = keyName:lower()

        if keyName == "b" or keyName == "backspace" then
            state.phase = "list"
            ViewPeripherals.draw(ctx)
            return nil
        end
    end

    return nil
end

return ViewPeripherals
