-- Pairing.lua
-- Consolidated swarm pairing logic
-- Single source of truth for all pairing operations

local Protocol = mpm('net/Protocol')
local Crypto = mpm('net/Crypto')

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
-- @param callbacks Table with: onStatus(msg), onSuccess(secret, pairingCode, zoneId), onCancel()
-- @return success, secret, pairingCode
function Pairing.acceptFromPocket(callbacks)
    callbacks = callbacks or {}

    local modem = peripheral.find("modem")
    if not modem then
        return false, nil, nil, "No modem found"
    end

    local modemName = peripheral.getName(modem)
    local modemType = modem.isWireless() and "wireless" or "wired"

    -- Generate one-time token
    local token = Pairing.generateToken()
    local computerId = os.getComputerID()
    local computerLabel = os.getComputerLabel() or ("Computer #" .. computerId)

    -- Open modem
    local wasOpen = rednet.isOpen(modemName)
    if not wasOpen then
        rednet.open(modemName)
    end

    if callbacks.onStatus then
        callbacks.onStatus("Waiting for pocket pairing...")
    end

    -- Broadcast PAIR_READY
    local msg = Protocol.createPairReady(token, computerLabel, computerId)
    rednet.broadcast(msg, Pairing.PROTOCOL)

    -- Wait for response
    local startTime = os.epoch("utc")
    local deadline = startTime + (Pairing.TOKEN_VALIDITY * 1000)
    local lastBroadcast = startTime
    local success = false
    local resultSecret, resultCode, resultZoneId

    while os.epoch("utc") < deadline do
        -- Re-broadcast every 3 seconds
        local now = os.epoch("utc")
        if now - lastBroadcast > 3000 then
            rednet.broadcast(msg, Pairing.PROTOCOL)
            lastBroadcast = now
        end

        local timer = os.startTimer(0.5)
        local event, p1, p2, p3 = os.pullEvent()

        if event == "rednet_message" then
            local senderId = p1
            local response = p2
            local msgProtocol = p3

            if msgProtocol == Pairing.PROTOCOL and type(response) == "table" then
                if response.type == Protocol.MessageType.PAIR_DELIVER then
                    -- Verify token
                    if response.data and response.data.token == token then
                        resultSecret = response.data.secret
                        resultCode = response.data.pairingCode
                        resultZoneId = response.data.zoneId

                        -- Send confirmation
                        local complete = Protocol.createPairComplete(computerLabel)
                        rednet.send(senderId, complete, Pairing.PROTOCOL)

                        success = true
                        break
                    end
                elseif response.type == Protocol.MessageType.PAIR_REJECT then
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

    -- Cleanup
    if not wasOpen then
        rednet.close(modemName)
    end

    if success and callbacks.onSuccess then
        callbacks.onSuccess(resultSecret, resultCode, resultZoneId)
    end

    return success, resultSecret, resultCode, resultZoneId
end

-- =============================================================================
-- ZONE SIDE: Host pairing session (share secret with code)
-- =============================================================================

-- Zone hosts pairing, waiting for other zones to join with code
-- @param secret The swarm secret to share
-- @param pairingCode The pairing code others must enter
-- @param zoneId Zone identifier
-- @param zoneName Zone display name
-- @param callbacks Table with: onStatus(msg), onJoin(computerId), onCancel()
-- @return clientsJoined count
function Pairing.hostSession(secret, pairingCode, zoneId, zoneName, callbacks)
    callbacks = callbacks or {}

    local modem = peripheral.find("modem")
    if not modem then
        return 0, "No modem found"
    end

    local modemName = peripheral.getName(modem)
    local wasOpen = rednet.isOpen(modemName)
    if not wasOpen then
        rednet.open(modemName)
    end

    if callbacks.onStatus then
        callbacks.onStatus("Hosting pairing session - Code: " .. pairingCode)
    end

    local running = true
    local clientsJoined = 0

    while running do
        local timer = os.startTimer(0.5)
        local event, p1, p2, p3 = os.pullEvent()

        if event == "rednet_message" then
            local senderId = p1
            local message = p2
            local msgProtocol = p3

            if msgProtocol == Pairing.PROTOCOL and type(message) == "table" then
                if message.type == "pair_request" then
                    if message.code == pairingCode then
                        -- Valid code - send secret
                        local response = {
                            type = "pair_response",
                            success = true,
                            secret = secret,
                            pairingCode = pairingCode,
                            zoneId = zoneId,
                            zoneName = zoneName
                        }
                        rednet.send(senderId, response, Pairing.PROTOCOL)

                        clientsJoined = clientsJoined + 1
                        if callbacks.onJoin then
                            callbacks.onJoin(senderId)
                        end
                    else
                        -- Invalid code
                        local response = {
                            type = "pair_response",
                            success = false,
                            error = "Invalid pairing code"
                        }
                        rednet.send(senderId, response, Pairing.PROTOCOL)
                    end
                end
            end
        elseif event == "key" then
            if p1 == keys.q then
                running = false
                if callbacks.onCancel then
                    callbacks.onCancel()
                end
            end
        end
    end

    if not wasOpen then
        rednet.close(modemName)
    end

    return clientsJoined
end

-- =============================================================================
-- ZONE SIDE: Join existing swarm with code
-- =============================================================================

-- Zone joins swarm by entering pairing code
-- @param code The pairing code to use
-- @param callbacks Table with: onStatus(msg), onSuccess(response), onFail(error)
-- @return success, secret, pairingCode, zoneId, zoneName
function Pairing.joinWithCode(code, callbacks)
    callbacks = callbacks or {}

    local modem = peripheral.find("modem")
    if not modem then
        return false, nil, nil, nil, nil, "No modem found"
    end

    local modemName = peripheral.getName(modem)
    local wasOpen = rednet.isOpen(modemName)
    if not wasOpen then
        rednet.open(modemName)
    end

    if callbacks.onStatus then
        callbacks.onStatus("Searching for swarm host...")
    end

    -- Broadcast pair request
    rednet.broadcast({ type = "pair_request", code = code }, Pairing.PROTOCOL)

    -- Wait for response
    local deadline = os.epoch("utc") + (Pairing.RESPONSE_TIMEOUT * 1000)
    local success = false
    local resultSecret, resultCode, resultZoneId, resultZoneName

    while os.epoch("utc") < deadline do
        local senderId, response, protocol = rednet.receive(Pairing.PROTOCOL, 1)

        if response and type(response) == "table" then
            if response.type == "pair_response" then
                if response.success then
                    resultSecret = response.secret
                    resultCode = response.pairingCode
                    resultZoneId = response.zoneId
                    resultZoneName = response.zoneName
                    success = true

                    if callbacks.onSuccess then
                        callbacks.onSuccess(response)
                    end
                    break
                else
                    if callbacks.onFail then
                        callbacks.onFail(response.error or "Invalid code")
                    end
                    break
                end
            end
        end
    end

    if not wasOpen then
        rednet.close(modemName)
    end

    if not success and not resultSecret then
        if callbacks.onFail then
            callbacks.onFail("No response from host")
        end
    end

    return success, resultSecret, resultCode, resultZoneId, resultZoneName
end

-- =============================================================================
-- POCKET SIDE: Deliver secret to waiting computer
-- =============================================================================

-- Pocket listens for PAIR_READY and delivers secret to selected computer
-- @param secret The swarm secret to deliver
-- @param pairingCode The swarm pairing code
-- @param zoneId Zone identifier (optional)
-- @param zoneName Zone display name (optional)
-- @param callbacks Table with: onReady(computer), onComplete(computer), onCancel()
-- @param timeout Timeout in seconds (default 30)
-- @return success, pairedComputer
function Pairing.deliverToPending(secret, pairingCode, zoneId, zoneName, callbacks, timeout)
    callbacks = callbacks or {}
    timeout = timeout or 30

    local modem = peripheral.find("modem")
    if not modem then
        return false, nil, "No modem found"
    end

    local modemName = peripheral.getName(modem)
    local wasOpen = rednet.isOpen(modemName)
    if not wasOpen then
        rednet.open(modemName)
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
                    -- Add/update pending list
                    local found = false
                    for i, pair in ipairs(pendingPairs) do
                        if pair.senderId == senderId then
                            pair.timestamp = os.epoch("utc")
                            pair.token = message.data.token
                            found = true
                            break
                        end
                    end

                    if not found then
                        local newPair = {
                            senderId = senderId,
                            token = message.data.token,
                            label = message.data.label or ("Computer #" .. senderId),
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
                -- Deliver secret to selected computer
                local pair = pendingPairs[selectedIndex]

                local deliverMsg = Protocol.createPairDeliver(
                    pair.token,
                    secret,
                    pairingCode,
                    zoneId,
                    zoneName
                )

                rednet.send(pair.senderId, deliverMsg, Pairing.PROTOCOL)

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

                -- Remove from pending if no confirmation
                table.remove(pendingPairs, selectedIndex)
                if selectedIndex > #pendingPairs then
                    selectedIndex = math.max(0, #pendingPairs)
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

    if not wasOpen then
        rednet.close(modemName)
    end

    return success, pairedComputer
end

-- Get list of pending computers (for UI rendering)
function Pairing.getPendingList()
    -- This would be used with a modified version that doesn't block
    -- For now, deliverToPending handles its own UI
    return {}
end

return Pairing
