-- AddComputer.lua
-- Computer pairing flow for shelfos-swarm pocket computer
-- Multi-phase wizard: scanning -> selection -> code entry -> pairing result
-- Uses TermUI for styled rendering, ScreenManager for navigation

local TermUI = mpm('ui/TermUI')
local Protocol = mpm('net/Protocol')
local Crypto = mpm('net/Crypto')
local Pairing = mpm('net/Pairing')
local ModemUtils = mpm('utils/ModemUtils')
local Keys = mpm('utils/Keys')
local Core = mpm('ui/Core')

local AddComputer = {}

-- Internal state
local state = {
    phase = "scanning",  -- "scanning", "selecting", "code_entry", "pairing", "success", "error"
    pendingComputers = {},
    selectedComputer = nil,
    spinnerFrame = 0,
    errorMsg = nil,
    successMsg = nil,
    pairingCreds = nil,
    spinnerTimer = nil,
    scanStartedAt = 0
}

local PAIR_PROTOCOL = "shelfos_pair"
local SCAN_TIMEOUT_MS = 60000
local PENDING_STALE_MS = 15000

local function prunePending()
    local cutoff = os.epoch("utc") - PENDING_STALE_MS
    local removed = false
    for i = #state.pendingComputers, 1, -1 do
        if (state.pendingComputers[i].lastSeen or 0) < cutoff then
            table.remove(state.pendingComputers, i)
            removed = true
        end
    end
    return removed
end

local function upsertPending(senderId, msg)
    if type(msg) ~= "table" or msg.type ~= Protocol.MessageType.PAIR_READY then
        return false
    end

    local computerId = msg.data.computerId or ("computer_" .. senderId)
    local computerLabel = msg.data.label or ("Computer " .. senderId)
    local now = os.epoch("utc")

    for _, c in ipairs(state.pendingComputers) do
        if c.id == computerId then
            c.lastSeen = now
            c.senderId = senderId
            c.label = computerLabel
            return false
        end
    end

    table.insert(state.pendingComputers, {
        id = computerId,
        senderId = senderId,
        label = computerLabel,
        lastSeen = now
    })
    return true
end

function AddComputer.onEnter(ctx, args)
    state.phase = "scanning"
    state.pendingComputers = {}
    state.selectedComputer = nil
    state.spinnerFrame = 0
    state.errorMsg = nil
    state.successMsg = nil
    state.pairingCreds = nil
    state.spinnerTimer = nil
    state.scanStartedAt = os.epoch("utc")

    -- Open modem
    local ok, modemName, modemType = ModemUtils.open(true)
    if not ok then
        state.phase = "error"
        state.errorMsg = "No modem found. Attach an ender modem."
    end
end

function AddComputer.draw(ctx)
    TermUI.clear()
    TermUI.drawTitleBar("Add Computer")

    if state.phase == "scanning" then
        AddComputer.drawScanning(ctx)
    elseif state.phase == "selecting" then
        AddComputer.drawSelecting(ctx)
    elseif state.phase == "code_entry" then
        AddComputer.drawCodeEntry(ctx)
    elseif state.phase == "pairing" then
        AddComputer.drawPairing(ctx)
    elseif state.phase == "success" then
        AddComputer.drawSuccess(ctx)
    elseif state.phase == "error" then
        AddComputer.drawError(ctx)
    end
end

function AddComputer.drawScanning(ctx)
    local y = 3

    TermUI.drawText(2, y, "On the target computer:", colors.lightGray)
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

    -- Computer count
    local elapsedMs = os.epoch("utc") - state.scanStartedAt
    local remaining = math.max(0, math.ceil((SCAN_TIMEOUT_MS - elapsedMs) / 1000))
    TermUI.drawText(2, y, "Timeout in: " .. remaining .. "s", colors.gray)
    y = y + 1

    local computerCount = #state.pendingComputers
    if computerCount > 0 then
        local countColor = colors.lime
        TermUI.drawText(2, y, "Found: " .. computerCount .. " computer(s)", countColor)
        y = y + 1

        -- Show computer names
        for i, c in ipairs(state.pendingComputers) do
            if y < ctx.height - 2 then
                TermUI.drawText(4, y, c.label, colors.lightGray)
                y = y + 1
            end
        end

        y = y + 1
        TermUI.drawText(2, y, "Press [S] to select", colors.yellow)
    else
        TermUI.drawText(2, y, "Found: 0 computers", colors.lightGray)
    end

    TermUI.drawStatusBar({{ key = "Q", label = "Cancel" }})
end

function AddComputer.drawSelecting(ctx)
    local y = 3

    TermUI.drawText(2, y, "Select a computer to pair:", colors.lightGray)
    y = y + 2

    for i, c in ipairs(state.pendingComputers) do
        if i <= 9 and y < ctx.height - 3 then
            -- Number key
            term.setCursorPos(2, y)
            term.setTextColor(colors.yellow)
            term.write("[" .. i .. "]")
            term.setTextColor(colors.lime)
            term.write(" " .. Core.truncate(c.label, ctx.width - 8))
            y = y + 1

            -- Details
            term.setCursorPos(6, y)
            term.setTextColor(colors.lightGray)
            term.write("ID: " .. c.senderId)
            y = y + 1
        end
    end

    term.setTextColor(colors.white)

    TermUI.drawStatusBar({{ key = "B", label = "Back" }})
end

function AddComputer.drawCodeEntry(ctx)
    local computer = state.selectedComputer
    local y = 3

    TermUI.drawText(2, y, "Pair Computer", colors.white)
    y = y + 2

    TermUI.drawInfoLine(y, "Computer", computer.label, colors.lime)
    y = y + 1
    TermUI.drawInfoLine(y, "ID", "#" .. computer.senderId, colors.lightGray)
    y = y + 2

    TermUI.drawText(2, y, "Enter the CODE shown on", colors.lightGray)
    y = y + 1
    TermUI.drawText(2, y, "the computer's screen:", colors.lightGray)
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
    local codeKeys = Pairing.getCodeKeyCandidates(enteredCode)

    if #codeKeys == 0 then
        state.errorMsg = "Code too short - cancelled"
        state.phase = "error"
        AddComputer.draw(ctx)
        return
    end

    -- Transition to pairing phase
    state.phase = "pairing"
    AddComputer.draw(ctx)

    -- Reserve credentials; commit only after PAIR_COMPLETE.
    local authority = ctx.app.authority
    local hasReserve = type(authority.reservePairingCredentials) == "function"
    local hasCommit = type(authority.commitPairingCredentials) == "function"
    local hasCancel = type(authority.cancelPairingCredentials) == "function"
    local isLegacySingleStep = false

    local creds, err
    if hasReserve then
        creds, err = authority:reservePairingCredentials(computer.id, computer.label)
    else
        isLegacySingleStep = true
        creds, err = authority:issueCredentials(computer.id, computer.label)
    end

    if not creds then
        state.errorMsg = "Failed: " .. (err or "Unknown error")
        state.phase = "error"
        AddComputer.draw(ctx)
        return
    end

    state.pairingCreds = creds

    -- Create and send PAIR_DELIVER
    local deliverMsg = Protocol.createPairDeliver(creds.swarmSecret, creds.computerId)

    -- Send equivalent key-format variants (raw/compact/dashed) so formatting
    -- differences in user input cannot break pairing.
    for _, codeKey in ipairs(codeKeys) do
        local signedEnvelope = Crypto.wrapWith(deliverMsg, codeKey)
        rednet.send(computer.senderId, signedEnvelope, PAIR_PROTOCOL)
    end

    -- Wait for PAIR_COMPLETE
    local deadline = os.epoch("utc") + 5000
    while os.epoch("utc") < deadline do
        local timer = os.startTimer(0.5)
        local event, p1, p2, p3 = os.pullEvent()

        if event == "rednet_message" and p1 == computer.senderId then
            if p3 == PAIR_PROTOCOL and type(p2) == "table" then
                if p2.type == Protocol.MessageType.PAIR_COMPLETE then
                    if hasCommit then
                        local committed, commitErr = authority:commitPairingCredentials(computer.id, computer.label)
                        if not committed then
                            if hasCancel then
                                authority:cancelPairingCredentials(computer.id)
                            end
                            state.errorMsg = "Pairing acknowledged but save failed: " .. (commitErr or "Unknown error")
                            state.phase = "error"
                            AddComputer.draw(ctx)
                            return
                        end
                        state.pairingCreds = committed
                    end

                    state.successMsg = computer.label .. " joined swarm"
                    state.phase = "success"
                    AddComputer.draw(ctx)
                    return
                end
            end
        end
    end

    -- Timeout: wrong code
    state.errorMsg = "No response - check code was correct"
    if hasCancel then
        authority:cancelPairingCredentials(computer.id)
    elseif isLegacySingleStep and type(authority.removeComputer) == "function" then
        authority:removeComputer(computer.id)
    end
    state.phase = "error"
    AddComputer.draw(ctx)
end

function AddComputer.drawPairing(ctx)
    local y = math.floor(ctx.height / 2) - 1
    TermUI.drawSpinner(y, "Issuing credentials...", state.spinnerFrame)
    TermUI.drawText(2, y + 1, "Waiting for confirmation...", colors.lightGray)
end

function AddComputer.drawSuccess(ctx)
    local y = 4

    TermUI.drawText(2, y, "Computer Paired!", colors.lime)
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

function AddComputer.drawError(ctx)
    local y = math.floor(ctx.height / 2) - 1

    TermUI.drawText(2, y, "Error", colors.red)
    y = y + 1
    TermUI.drawWrapped(y, state.errorMsg or "Unknown error", colors.orange, 2, 3)

    TermUI.drawStatusBar("Press any key to go back...")
end

function AddComputer.handleEvent(ctx, event, p1, p2, p3)
    if state.phase == "scanning" then
        return AddComputer.handleScanning(ctx, event, p1, p2, p3)
    elseif state.phase == "selecting" then
        return AddComputer.handleSelecting(ctx, event, p1, p2, p3)
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

function AddComputer.handleScanning(ctx, event, p1, p2, p3)
    local changedByPrune = prunePending()
    if changedByPrune then
        AddComputer.draw(ctx)
    end

    local elapsedMs = os.epoch("utc") - state.scanStartedAt
    if elapsedMs >= SCAN_TIMEOUT_MS and #state.pendingComputers == 0 then
        state.errorMsg = "No pairing requests detected. Start pairing on the target computer, then retry."
        state.phase = "error"
        AddComputer.draw(ctx)
        return nil
    end

    if event == "key" then
        local keyName = keys.getName(p1)
        if keyName then
            keyName = keyName:lower()
            if keyName == "q" then
                return "pop"
            elseif keyName == "s" and #state.pendingComputers > 0 then
                state.phase = "selecting"
                AddComputer.draw(ctx)
                return nil
            end
        end

    elseif event == "timer" then
        -- Update spinner
        state.spinnerFrame = state.spinnerFrame + 1
        AddComputer.draw(ctx)

    elseif event == "rednet_message" and p3 == PAIR_PROTOCOL then
        local senderId = p1
        local msg = p2
        local changed = upsertPending(senderId, msg)
        if changed then
            AddComputer.draw(ctx)
        end
    end

    -- Keep a timer running for spinner animation (cancel previous to prevent leak)
    if state.spinnerTimer then
        os.cancelTimer(state.spinnerTimer)
    end
    state.spinnerTimer = os.startTimer(0.5)

    return nil
end

function AddComputer.handleSelecting(ctx, event, p1, p2, p3)
    if prunePending() then
        if #state.pendingComputers == 0 then
            state.phase = "scanning"
        end
        AddComputer.draw(ctx)
    end

    if event == "key" then
        local keyName = keys.getName(p1)
        if not keyName then return nil end
        keyName = keyName:lower()

        if keyName == "b" or keyName == "backspace" then
            state.phase = "scanning"
            AddComputer.draw(ctx)
            return nil
        end

        -- Number selection
        local num = Keys.getNumber(keyName)
        if num and num >= 1 and num <= #state.pendingComputers then
            state.selectedComputer = state.pendingComputers[num]
            state.phase = "code_entry"
            AddComputer.draw(ctx)
            return nil
        end

    elseif event == "rednet_message" and p3 == PAIR_PROTOCOL then
        -- Continue collecting computers while selecting
        local senderId = p1
        local msg = p2

        if upsertPending(senderId, msg) then
            AddComputer.draw(ctx)
        end
    end

    return nil
end

return AddComputer
