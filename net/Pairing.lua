-- Pairing.lua
-- Consolidated swarm pairing logic
-- Single source of truth for all pairing operations
--
-- SECURITY MODEL:
-- The pairing code is DISPLAYED on the zone's screen (never broadcast).
-- The user must physically see the code and enter it on the pocket.
-- PAIR_DELIVER is signed with the code as an ephemeral key.
-- This prevents interception attacks - attacker would need physical access.

local Protocol = mpm('net/Protocol')
local Crypto = mpm('net/Crypto')
local ModemUtils = mpm('utils/ModemUtils')

local Pairing = {}

-- Protocol for pairing messages
Pairing.PROTOCOL = "shelfos_pair"

-- Timeouts
Pairing.TOKEN_VALIDITY = 60  -- seconds
Pairing.RESPONSE_TIMEOUT = 10  -- seconds

-- Generate a random token for one-time pairing verification
function Pairing.generateToken()
    local chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    local token = ""
    for i = 1, 16 do
        local idx = math.random(1, #chars)
        token = token .. chars:sub(idx, idx)
    end
    return token
end

-- Generate a human-readable pairing code (XXXX-XXXX format)
function Pairing.generateCode()
    local chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    local code = ""
    for i = 1, 8 do
        if i == 5 then code = code .. "-" end
        local idx = math.random(1, #chars)
        code = code .. chars:sub(idx, idx)
    end
    return code
end

-- Generate a new swarm secret
function Pairing.generateSecret()
    return Crypto.generateSecret()
end

-- =============================================================================
-- ZONE SIDE: Accept pairing from pocket (receive secret)
-- =============================================================================

-- Zone broadcasts PAIR_READY and waits for pocket to deliver secret
-- SECURITY: The displayCode is shown on screen only (NEVER broadcast)
-- The pocket must enter this code, which is used to sign PAIR_DELIVER
-- @param callbacks Table with: onStatus(msg), onDisplayCode(code), onSuccess(secret, zoneId), onCancel(reason)
-- @return success, secret, zoneId
function Pairing.acceptFromPocket(callbacks)
    callbacks = callbacks or {}

    -- Open modem with wireless preference (also closes other modems)
    local ok, modemName, modemType = ModemUtils.open(true)
    if not ok then
        return false, nil, nil, nil, "No modem found"
    end

    -- Generate display-only code (NEVER sent over network)
    local displayCode = Pairing.generateCode()
    local computerId = os.getComputerID()
    local computerLabel = os.getComputerLabel() or ("Computer #" .. computerId)

    -- Notify caller of the display code (for UI rendering)
    if callbacks.onDisplayCode then
        callbacks.onDisplayCode(displayCode)
    end

    if callbacks.onStatus then
        callbacks.onStatus("Broadcasting on " .. modemType .. " (" .. modemName .. ")...")
    end

    -- Broadcast PAIR_READY - NOTE: NO code/token in message (security)
    -- Only send label and computerId for identification
    local msg = Protocol.createPairReady(nil, computerLabel, computerId)
    rednet.broadcast(msg, Pairing.PROTOCOL)

    -- Wait for response
    local startTime = os.epoch("utc")
    local deadline = startTime + (Pairing.TOKEN_VALIDITY * 1000)
    local lastBroadcast = startTime
    local success = false
    local resultSecret, resultZoneId

    while os.epoch("utc") < deadline do
        -- Re-broadcast presence every 3 seconds
        local now = os.epoch("utc")
        if now - lastBroadcast > 3000 then
            rednet.broadcast(msg, Pairing.PROTOCOL)
            lastBroadcast = now

            if callbacks.onStatus then
                local remaining = math.ceil((deadline - now) / 1000)
                callbacks.onStatus("Waiting... " .. remaining .. "s")
            end
        end

        local timer = os.startTimer(0.5)
        local event, p1, p2, p3 = os.pullEvent()

        if event == "rednet_message" then
            local senderId = p1
            local envelope = p2
            local msgProtocol = p3

            if msgProtocol == Pairing.PROTOCOL and type(envelope) == "table" then
                -- Check for signed PAIR_DELIVER (verify with display code)
                if envelope.v and envelope.p and envelope.s then
                    -- This is a signed envelope, verify with our display code
                    local data, err = Crypto.unwrapWith(envelope, displayCode)

                    if data and data.type == Protocol.MessageType.PAIR_DELIVER then
                        -- Signature valid - extract credentials
                        -- Support both formats: simple (secret, zoneId) and full (credentials table)
                        local creds = data.data and data.data.credentials
                        if creds then
                            -- Full credentials from SwarmAuthority
                            resultSecret = creds.swarmSecret
                            resultZoneId = creds.zoneId
                        else
                            -- Simple format (legacy)
                            resultSecret = data.data and data.data.secret
                            resultZoneId = data.data and data.data.zoneId
                        end

                        if resultSecret then
                            -- Send confirmation (unsigned, just acknowledgment)
                            local complete = Protocol.createPairComplete(computerLabel)
                            rednet.send(senderId, complete, Pairing.PROTOCOL)

                            success = true
                            break
                        end
                    end
                    -- Invalid signature = wrong code entered, ignore silently
                elseif envelope.type == Protocol.MessageType.PAIR_REJECT then
                    if callbacks.onCancel then
                        callbacks.onCancel("Rejected by pocket")
                    end
                    break
                end
            end
        elseif event == "key" then
            if p1 == keys.q then
                local reject = Protocol.createPairReject("User cancelled")
                rednet.broadcast(reject, Pairing.PROTOCOL)
                if callbacks.onCancel then
                    callbacks.onCancel("User cancelled")
                end
                break
            end
        end
    end

    -- Note: Leave modem open - caller will use it for network init after pairing

    if success and callbacks.onSuccess then
        callbacks.onSuccess(resultSecret, resultZoneId)
    end

    return success, resultSecret, resultZoneId
end

-- =============================================================================
-- POCKET SIDE: Deliver secret to waiting computer
-- =============================================================================

-- Pocket listens for PAIR_READY and delivers secret to selected computer
-- SECURITY: User must enter the code displayed on the zone's screen
-- PAIR_DELIVER is signed with that code as an ephemeral key
-- @param secret The swarm secret to deliver
-- @param zoneId Zone identifier (optional)
-- @param callbacks Table with: onReady(computer), onCodePrompt(computer, callback), onComplete(computer), onCancel(), onCodeInvalid()
-- @param timeout Timeout in seconds (default 30)
-- @return success, pairedComputer
function Pairing.deliverToPending(secret, zoneId, callbacks, timeout)
    callbacks = callbacks or {}
    timeout = timeout or 30

    -- Open modem with wireless preference (also closes other modems)
    local ok, modemName, modemType = ModemUtils.open(true)
    if not ok then
        return false, nil, "No modem found"
    end

    local pendingPairs = {}
    local selectedIndex = 0
    local deadline = os.epoch("utc") + (timeout * 1000)
    local success = false
    local pairedComputer = nil

    while os.epoch("utc") < deadline do
        local timer = os.startTimer(0.3)
        local event, p1, p2, p3 = os.pullEvent()

        if event == "rednet_message" then
            local senderId = p1
            local message = p2
            local msgProtocol = p3

            if msgProtocol == Pairing.PROTOCOL and type(message) == "table" then
                if message.type == Protocol.MessageType.PAIR_READY then
                    -- Add/update pending list (no token expected anymore)
                    local found = false
                    for i, pair in ipairs(pendingPairs) do
                        if pair.senderId == senderId then
                            pair.timestamp = os.epoch("utc")
                            found = true
                            break
                        end
                    end

                    if not found then
                        local newPair = {
                            senderId = senderId,
                            label = message.data.label or ("Computer #" .. senderId),
                            computerId = message.data.computerId or senderId,
                            timestamp = os.epoch("utc")
                        }
                        table.insert(pendingPairs, newPair)
                        if selectedIndex == 0 then
                            selectedIndex = 1
                        end

                        if callbacks.onReady then
                            callbacks.onReady(newPair)
                        end
                    end

                elseif message.type == Protocol.MessageType.PAIR_COMPLETE then
                    success = true
                    pairedComputer = message.data and message.data.label
                    if callbacks.onComplete then
                        callbacks.onComplete(pairedComputer)
                    end
                    break
                end
            end

        elseif event == "key" then
            if p1 == keys.q then
                if callbacks.onCancel then
                    callbacks.onCancel()
                end
                break

            elseif p1 == keys.up then
                if selectedIndex > 1 then
                    selectedIndex = selectedIndex - 1
                end

            elseif p1 == keys.down then
                if selectedIndex < #pendingPairs then
                    selectedIndex = selectedIndex + 1
                end

            elseif p1 == keys.enter and selectedIndex > 0 and selectedIndex <= #pendingPairs then
                -- User selected a computer - need to get the display code
                local pair = pendingPairs[selectedIndex]

                -- Prompt for the code shown on the zone's screen
                local enteredCode = nil
                if callbacks.onCodePrompt then
                    enteredCode = callbacks.onCodePrompt(pair)
                else
                    -- Fallback: simple terminal prompt
                    print("")
                    print("Enter code shown on " .. pair.label .. ":")
                    write("> ")
                    enteredCode = read():upper():gsub("%s", "")
                end

                if not enteredCode or #enteredCode < 4 then
                    if callbacks.onCodeInvalid then
                        callbacks.onCodeInvalid("Code too short")
                    end
                else
                    -- Create PAIR_DELIVER message and sign with entered code
                    local deliverMsg = Protocol.createPairDeliver(secret, zoneId)

                    -- Sign the message with the entered code as ephemeral key
                    local signedEnvelope = Crypto.wrapWith(deliverMsg, enteredCode)
                    rednet.send(pair.senderId, signedEnvelope, Pairing.PROTOCOL)

                    -- Wait briefly for confirmation
                    local confirmDeadline = os.epoch("utc") + 5000
                    while os.epoch("utc") < confirmDeadline do
                        local cTimer = os.startTimer(0.5)
                        local cEvent, cp1, cp2, cp3 = os.pullEvent()

                        if cEvent == "rednet_message" and cp1 == pair.senderId then
                            if cp3 == Pairing.PROTOCOL and type(cp2) == "table" then
                                if cp2.type == Protocol.MessageType.PAIR_COMPLETE then
                                    success = true
                                    pairedComputer = pair.label
                                    if callbacks.onComplete then
                                        callbacks.onComplete(pairedComputer)
                                    end
                                    break
                                end
                            end
                        end
                    end

                    if success then break end

                    -- No confirmation = wrong code or network issue
                    if callbacks.onCodeInvalid then
                        callbacks.onCodeInvalid("No response - check code")
                    end

                    -- Remove from pending
                    table.remove(pendingPairs, selectedIndex)
                    if selectedIndex > #pendingPairs then
                        selectedIndex = math.max(0, #pendingPairs)
                    end
                end
            end
        end

        -- Clean up stale entries (older than 15 seconds)
        local cleanTime = os.epoch("utc") - 15000
        for i = #pendingPairs, 1, -1 do
            if pendingPairs[i].timestamp < cleanTime then
                table.remove(pendingPairs, i)
                if selectedIndex > #pendingPairs then
                    selectedIndex = math.max(0, #pendingPairs)
                end
            end
        end
    end

    -- Note: Leave modem open - caller's App keeps it open

    return success, pairedComputer
end

-- Get list of pending computers (for UI rendering)
function Pairing.getPendingList()
    -- This would be used with a modified version that doesn't block
    -- For now, deliverToPending handles its own UI
    return {}
end

return Pairing
