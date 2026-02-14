-- AddZone.lua
-- Zone pairing flow for shelfos-swarm pocket computer
-- Multi-phase wizard: scanning -> selection -> code entry -> pairing result
-- Uses TermUI for styled rendering, ScreenManager for navigation

local TermUI = mpm('shelfos-swarm/ui/TermUI')
local Protocol = mpm('net/Protocol')
local Crypto = mpm('net/Crypto')
local ModemUtils = mpm('utils/ModemUtils')
local Keys = mpm('utils/Keys')
local Core = mpm('ui/Core')

local AddZone = {}

-- Internal state
local state = {
    phase = "scanning",  -- "scanning", "selecting", "code_entry", "pairing", "success", "error"
    pendingZones = {},
    selectedZone = nil,
    spinnerFrame = 0,
    errorMsg = nil,
    successMsg = nil,
    pairingCreds = nil
}

local PAIR_PROTOCOL = "shelfos_pair"
local SCAN_TIMEOUT_MS = 60000

function AddZone.onEnter(ctx, args)
    state.phase = "scanning"
    state.pendingZones = {}
    state.selectedZone = nil
    state.spinnerFrame = 0
    state.errorMsg = nil
    state.successMsg = nil
    state.pairingCreds = nil

    -- Open modem
    local ok, modemName, modemType = ModemUtils.open(true)
    if not ok then
        state.phase = "error"
        state.errorMsg = "No modem found. Attach an ender modem."
    end
end

function AddZone.draw(ctx)
    TermUI.clear()
    TermUI.drawTitleBar("Add Zone")

    if state.phase == "scanning" then
        AddZone.drawScanning(ctx)
    elseif state.phase == "selecting" then
        AddZone.drawSelecting(ctx)
    elseif state.phase == "code_entry" then
        AddZone.drawCodeEntry(ctx)
    elseif state.phase == "pairing" then
        AddZone.drawPairing(ctx)
    elseif state.phase == "success" then
        AddZone.drawSuccess(ctx)
    elseif state.phase == "error" then
        AddZone.drawError(ctx)
    end
end

function AddZone.drawScanning(ctx)
    local y = 3

    TermUI.drawText(2, y, "On the zone computer:", colors.lightGray)
    y = y + 1
    TermUI.drawText(2, y, "1. Run: mpm run shelfos", colors.white)
    y = y + 1
    TermUI.drawText(2, y, "2. Press [L] > Accept", colors.white)
    y = y + 1
    TermUI.drawText(2, y, "3. Note the CODE shown", colors.white)
    y = y + 2

    -- Spinner
    TermUI.drawSpinner(y, "Scanning...", state.spinnerFrame)
    y = y + 2

    -- Zone count
    local zoneCount = #state.pendingZones
    if zoneCount > 0 then
        local countColor = colors.lime
        TermUI.drawText(2, y, "Found: " .. zoneCount .. " zone(s)", countColor)
        y = y + 1

        -- Show zone names
        for i, z in ipairs(state.pendingZones) do
            if y < ctx.height - 2 then
                TermUI.drawText(4, y, z.label, colors.lightGray)
                y = y + 1
            end
        end

        y = y + 1
        TermUI.drawText(2, y, "Press [S] to select a zone", colors.yellow)
    else
        TermUI.drawText(2, y, "Found: 0 zones", colors.lightGray)
    end

    TermUI.drawStatusBar({{ key = "Q", label = "Cancel" }})
end

function AddZone.drawSelecting(ctx)
    local y = 3

    TermUI.drawText(2, y, "Select a zone to pair:", colors.lightGray)
    y = y + 2

    for i, z in ipairs(state.pendingZones) do
        if i <= 9 and y < ctx.height - 3 then
            -- Number key
            term.setCursorPos(2, y)
            term.setTextColor(colors.yellow)
            term.write("[" .. i .. "]")
            term.setTextColor(colors.lime)
            term.write(" " .. Core.truncate(z.label, ctx.width - 8))
            y = y + 1

            -- Details
            term.setCursorPos(6, y)
            term.setTextColor(colors.lightGray)
            term.write("ID: " .. z.senderId)
            y = y + 1
        end
    end

    term.setTextColor(colors.white)

    TermUI.drawStatusBar({{ key = "B", label = "Back" }})
end

function AddZone.drawCodeEntry(ctx)
    local zone = state.selectedZone
    local y = 3

    TermUI.drawText(2, y, "Pair Zone", colors.white)
    y = y + 2

    TermUI.drawInfoLine(y, "Zone", zone.label, colors.lime)
    y = y + 1
    TermUI.drawInfoLine(y, "Computer", "#" .. zone.senderId, colors.lightGray)
    y = y + 2

    TermUI.drawText(2, y, "Enter the CODE shown on", colors.lightGray)
    y = y + 1
    TermUI.drawText(2, y, "the zone's screen:", colors.lightGray)
    y = y + 1
    TermUI.drawText(2, y, "(format: XXXX-XXXX)", colors.gray)
    y = y + 2

    -- Prompt
    term.setCursorPos(2, y)
    term.setTextColor(colors.yellow)
    term.write("> ")
    term.setTextColor(colors.white)

    local input = read()
    if not input then input = "" end
    local enteredCode = input:upper():gsub("%s", "")

    if #enteredCode < 4 then
        state.errorMsg = "Code too short - cancelled"
        state.phase = "error"
        AddZone.draw(ctx)
        return
    end

    -- Transition to pairing phase
    state.phase = "pairing"
    AddZone.draw(ctx)

    -- Issue credentials
    local creds, err = ctx.app.authority:issueCredentials(zone.id, zone.label)
    if not creds then
        state.errorMsg = "Failed: " .. (err or "Unknown error")
        state.phase = "error"
        AddZone.draw(ctx)
        return
    end

    state.pairingCreds = creds

    -- Create and send PAIR_DELIVER
    local deliverMsg = Protocol.createPairDeliver(creds.swarmSecret, creds.zoneId)
    deliverMsg.data.credentials = creds

    local signedEnvelope = Crypto.wrapWith(deliverMsg, enteredCode)
    rednet.send(zone.senderId, signedEnvelope, PAIR_PROTOCOL)

    -- Wait for PAIR_COMPLETE
    local deadline = os.epoch("utc") + 5000
    while os.epoch("utc") < deadline do
        local timer = os.startTimer(0.5)
        local event, p1, p2, p3 = os.pullEvent()

        if event == "rednet_message" and p1 == zone.senderId then
            if p3 == PAIR_PROTOCOL and type(p2) == "table" then
                if p2.type == Protocol.MessageType.PAIR_COMPLETE then
                    state.successMsg = zone.label .. " joined swarm"
                    state.phase = "success"
                    AddZone.draw(ctx)
                    return
                end
            end
        end
    end

    -- Timeout: wrong code
    state.errorMsg = "No response - check code was correct"
    ctx.app.authority:removeZone(zone.id)
    state.phase = "error"
    AddZone.draw(ctx)
end

function AddZone.drawPairing(ctx)
    local y = math.floor(ctx.height / 2) - 1
    TermUI.drawSpinner(y, "Issuing credentials...", state.spinnerFrame)
    TermUI.drawText(2, y + 1, "Waiting for confirmation...", colors.lightGray)
end

function AddZone.drawSuccess(ctx)
    local y = 4

    TermUI.drawText(2, y, "Zone Paired!", colors.lime)
    y = y + 2

    if state.successMsg then
        TermUI.drawText(2, y, state.successMsg, colors.white)
        y = y + 1
    end

    if state.pairingCreds then
        y = y + 1
        TermUI.drawInfoLine(y, "Fingerprint", state.pairingCreds.swarmFingerprint, colors.yellow)
    end

    TermUI.drawStatusBar("Press any key to continue...")
end

function AddZone.drawError(ctx)
    local y = math.floor(ctx.height / 2) - 1

    TermUI.drawText(2, y, "Error", colors.red)
    y = y + 1
    TermUI.drawWrapped(y, state.errorMsg or "Unknown error", colors.orange, 2, 3)

    TermUI.drawStatusBar("Press any key to go back...")
end

function AddZone.handleEvent(ctx, event, p1, p2, p3)
    if state.phase == "scanning" then
        return AddZone.handleScanning(ctx, event, p1, p2, p3)
    elseif state.phase == "selecting" then
        return AddZone.handleSelecting(ctx, event, p1, p2, p3)
    elseif state.phase == "code_entry" then
        -- read() handles events internally during drawCodeEntry
        return nil
    elseif state.phase == "pairing" then
        -- Handled internally during drawCodeEntry
        return nil
    elseif state.phase == "success" or state.phase == "error" then
        if event == "key" then
            return "pop"
        end
    end

    return nil
end

function AddZone.handleScanning(ctx, event, p1, p2, p3)
    if event == "key" then
        local keyName = keys.getName(p1)
        if keyName then
            keyName = keyName:lower()
            if keyName == "q" then
                return "pop"
            elseif keyName == "s" and #state.pendingZones > 0 then
                state.phase = "selecting"
                AddZone.draw(ctx)
                return nil
            end
        end

    elseif event == "timer" then
        -- Update spinner
        state.spinnerFrame = state.spinnerFrame + 1
        AddZone.draw(ctx)

    elseif event == "rednet_message" and p3 == PAIR_PROTOCOL then
        local senderId = p1
        local msg = p2

        if type(msg) == "table" and msg.type == Protocol.MessageType.PAIR_READY then
            local zoneId = msg.data.computerId or ("zone_" .. senderId)
            local zoneLabel = msg.data.label or ("Zone " .. senderId)

            -- Check if already in list
            local found = false
            for _, z in ipairs(state.pendingZones) do
                if z.id == zoneId then
                    found = true
                    z.lastSeen = os.epoch("utc")
                    break
                end
            end

            if not found then
                table.insert(state.pendingZones, {
                    id = zoneId,
                    senderId = senderId,
                    label = zoneLabel,
                    lastSeen = os.epoch("utc")
                })
            end

            AddZone.draw(ctx)
        end
    end

    -- Keep a timer running for spinner animation
    os.startTimer(0.5)

    return nil
end

function AddZone.handleSelecting(ctx, event, p1, p2, p3)
    if event == "key" then
        local keyName = keys.getName(p1)
        if not keyName then return nil end
        keyName = keyName:lower()

        if keyName == "b" or keyName == "backspace" then
            state.phase = "scanning"
            AddZone.draw(ctx)
            return nil
        end

        -- Number selection
        local num = Keys.getNumber(keyName)
        if num and num >= 1 and num <= #state.pendingZones then
            state.selectedZone = state.pendingZones[num]
            state.phase = "code_entry"
            AddZone.draw(ctx)
            return nil
        end

    elseif event == "rednet_message" and p3 == PAIR_PROTOCOL then
        -- Continue collecting zones while selecting
        local senderId = p1
        local msg = p2

        if type(msg) == "table" and msg.type == Protocol.MessageType.PAIR_READY then
            local zoneId = msg.data.computerId or ("zone_" .. senderId)
            local zoneLabel = msg.data.label or ("Zone " .. senderId)

            local found = false
            for _, z in ipairs(state.pendingZones) do
                if z.id == zoneId then
                    found = true
                    z.lastSeen = os.epoch("utc")
                    break
                end
            end

            if not found then
                table.insert(state.pendingZones, {
                    id = zoneId,
                    senderId = senderId,
                    label = zoneLabel,
                    lastSeen = os.epoch("utc")
                })
                AddZone.draw(ctx)
            end
        end
    end

    return nil
end

return AddZone
