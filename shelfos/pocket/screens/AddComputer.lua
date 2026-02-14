-- AddComputer.lua
-- Screen flow for adding a computer to the swarm via pocket pairing
-- SECURITY: User must enter the code displayed on the zone's screen

local Protocol = mpm('net/Protocol')
local Crypto = mpm('net/Crypto')
local Pairing = mpm('net/Pairing')
local EventUtils = mpm('utils/EventUtils')

local AddComputer = {}

local PAIR_PROTOCOL = "shelfos_pair"
local TIMEOUT_SECONDS = 30
local STALE_THRESHOLD_MS = 15000  -- Remove entries older than 15 seconds

-- Load pocket configuration
-- @return secret, zoneId
local function loadConfig()
    local secret = nil
    local zoneId = "pocket_" .. os.getComputerID()

    -- Load secret
    local secretPath = "/shelfos_secret.txt"
    if fs.exists(secretPath) then
        local file = fs.open(secretPath, "r")
        if file then
            secret = file.readAll()
            file.close()
        end
    end

    -- Load pocket config for zoneId override
    local configPath = "/shelfos_pocket.config"
    if fs.exists(configPath) then
        local file = fs.open(configPath, "r")
        if file then
            local content = file.readAll()
            file.close()
            local ok, config = pcall(textutils.unserialize, content)
            if ok and config and config.zoneId then
                zoneId = config.zoneId
            end
        end
    end

    return secret, zoneId
end

-- Draw the main waiting screen
-- @param pendingPairs Table of pending pair requests
-- @param selectedIndex Currently selected index
-- @param deadline Timeout deadline timestamp
local function drawWaitingScreen(pendingPairs, selectedIndex, deadline)
    local now = os.epoch("utc")

    term.clear()
    term.setCursorPos(1, 1)
    print("=== Add Computer ===")
    print("")

    if #pendingPairs == 0 then
        print("Waiting for computers...")
        print("")
        print("On target: L -> Accept from pocket")
    else
        print("Computers requesting to join:")
        print("")
        for i, pair in ipairs(pendingPairs) do
            local marker = (i == selectedIndex) and "> " or "  "
            local age = math.floor((now - pair.timestamp) / 1000)
            print(marker .. i .. ". " .. pair.label)
            print("     ID: #" .. pair.senderId .. " (" .. age .. "s ago)")
        end
        print("")
        print("[Enter] Select  [Up/Down] Navigate")
    end

    print("")
    local remaining = math.ceil((deadline - now) / 1000)
    print("[Q] Cancel (" .. remaining .. "s)")
end

-- Draw the code entry screen
-- @param pair The selected pair request
local function drawCodeEntryScreen(pair)
    term.clear()
    term.setCursorPos(1, 1)
    print("=== Enter Pairing Code ===")
    print("")
    print("Computer: " .. pair.label)
    print("ID: #" .. pair.senderId)
    print("")
    print("Enter the code shown on")
    print("the computer's screen:")
    print("")
    write("> ")
end

-- Send PAIR_DELIVER to the target computer
-- @param pair Target pair info
-- @param enteredCode Code entered by user (used to sign the message)
-- @param secret Swarm secret
-- @param zoneId Zone ID
-- @return boolean success
local function sendPairDeliver(pair, enteredCode, secret, zoneId)
    print("")
    print("[*] Sending to " .. pair.label .. "...")

    -- Create PAIR_DELIVER and sign with entered code
    local deliverMsg = Protocol.createPairDeliver(secret, zoneId)

    -- Sign with the entered code as ephemeral key
    local signedEnvelope = Crypto.wrapWith(deliverMsg, enteredCode)
    rednet.send(pair.senderId, signedEnvelope, PAIR_PROTOCOL)

    -- Wait for confirmation
    local confirmDeadline = os.epoch("utc") + 5000

    while os.epoch("utc") < confirmDeadline do
        os.startTimer(0.5)
        local cEvent, cp1, cp2, cp3 = os.pullEvent()

        if cEvent == "rednet_message" and cp1 == pair.senderId then
            if cp3 == PAIR_PROTOCOL and type(cp2) == "table" then
                if cp2.type == Protocol.MessageType.PAIR_COMPLETE then
                    print("[*] " .. pair.label .. " joined swarm!")
                    return true
                end
            end
        end
    end

    return false
end

-- Handle keyboard input
-- @param key Key code
-- @param pendingPairs Table of pending pairs
-- @param selectedIndex Current selection
-- @return action ("cancel", "select", "up", "down", nil), newSelectedIndex
local function handleKeyInput(key, pendingPairs, selectedIndex)
    if key == keys.q then
        return "cancel", selectedIndex
    elseif key == keys.up then
        if selectedIndex > 1 then
            return "up", selectedIndex - 1
        end
    elseif key == keys.down then
        if selectedIndex < #pendingPairs then
            return "down", selectedIndex + 1
        end
    elseif key == keys.enter and selectedIndex > 0 and selectedIndex <= #pendingPairs then
        return "select", selectedIndex
    end
    return nil, selectedIndex
end

-- Handle PAIR_READY message
-- @param senderId Sender computer ID
-- @param message Protocol message
-- @param pendingPairs Table of pending pairs (modified)
-- @param selectedIndex Current selection
-- @return newSelectedIndex, needsRefresh
local function handlePairReady(senderId, message, pendingPairs, selectedIndex)
    -- Check if we already have this sender
    local found = false
    for _, pair in ipairs(pendingPairs) do
        if pair.senderId == senderId then
            pair.timestamp = os.epoch("utc")
            found = true
            break
        end
    end

    if not found then
        table.insert(pendingPairs, {
            senderId = senderId,
            label = message.data.label or ("Computer #" .. senderId),
            computerId = message.data.computerId or senderId,
            timestamp = os.epoch("utc")
        })
        -- Auto-select first one
        if selectedIndex == 0 then
            selectedIndex = 1
        end
    end

    return selectedIndex, true
end

-- Remove stale entries from pending pairs
-- @param pendingPairs Table of pending pairs (modified)
-- @param selectedIndex Current selection
-- @return newSelectedIndex
local function cleanupStalePairs(pendingPairs, selectedIndex)
    local cleanTime = os.epoch("utc") - STALE_THRESHOLD_MS
    for i = #pendingPairs, 1, -1 do
        if pendingPairs[i].timestamp < cleanTime then
            table.remove(pendingPairs, i)
            if selectedIndex > #pendingPairs then
                selectedIndex = math.max(0, #pendingPairs)
            end
        end
    end
    return selectedIndex
end

-- Run the add computer flow
-- @return boolean success
function AddComputer.run()
    -- Load configuration
    local secret, zoneId = loadConfig()

    if not secret then
        term.clear()
        term.setCursorPos(1, 1)
        print("[!] No swarm secret configured")
        print("    Configure pocket first")
        EventUtils.sleep(2)
        return false
    end

    -- Ensure modem is open
    local modem = peripheral.find("modem")
    if not modem then
        term.clear()
        term.setCursorPos(1, 1)
        print("[!] No modem found")
        EventUtils.sleep(2)
        return false
    end

    local modemName = peripheral.getName(modem)
    rednet.open(modemName)

    -- Initial screen
    term.clear()
    term.setCursorPos(1, 1)
    print("=== Add Computer ===")
    print("")
    print("Listening for computers")
    print("requesting to join...")
    print("")
    print("On the target computer:")
    print("  Press L -> 'Accept from pocket'")
    print("")
    print("[Q] Cancel")
    print("")

    -- State
    local pendingPairs = {}
    local selectedIndex = 0
    local lastRefresh = 0
    local deadline = os.epoch("utc") + (TIMEOUT_SECONDS * 1000)

    -- Main loop
    while os.epoch("utc") < deadline do
        -- Refresh display periodically
        local now = os.epoch("utc")
        if now - lastRefresh > 500 then
            drawWaitingScreen(pendingPairs, selectedIndex, deadline)
            lastRefresh = now
        end

        -- Wait for events
        os.startTimer(0.3)
        local event, p1, p2, p3 = os.pullEvent()

        if event == "rednet_message" then
            local senderId = p1
            local message = p2
            local msgProtocol = p3

            if msgProtocol == PAIR_PROTOCOL and type(message) == "table" then
                if message.type == Protocol.MessageType.PAIR_READY then
                    selectedIndex, _ = handlePairReady(senderId, message, pendingPairs, selectedIndex)
                    lastRefresh = 0

                elseif message.type == Protocol.MessageType.PAIR_COMPLETE then
                    print("")
                    print("[*] " .. (message.data and message.data.label or "Computer") .. " joined swarm!")
                    EventUtils.sleep(2)
                    return true
                end
            end

        elseif event == "key" then
            local action, newIndex = handleKeyInput(p1, pendingPairs, selectedIndex)
            selectedIndex = newIndex

            if action == "cancel" then
                return false

            elseif action == "select" then
                local pair = pendingPairs[selectedIndex]
                drawCodeEntryScreen(pair)

                local enteredCode = read():upper():gsub("%s", "")

                if #enteredCode < 4 then
                    print("")
                    print("[!] Code too short")
                    EventUtils.sleep(1)
                else
                    local success = sendPairDeliver(pair, enteredCode, secret, zoneId)
                    if success then
                        EventUtils.sleep(2)
                        return true
                    else
                        print("[!] No response - wrong code?")
                        EventUtils.sleep(2)
                        -- Remove from pending list
                        table.remove(pendingPairs, selectedIndex)
                        if selectedIndex > #pendingPairs then
                            selectedIndex = #pendingPairs
                        end
                    end
                end
                lastRefresh = 0

            elseif action == "up" or action == "down" then
                lastRefresh = 0
            end
        end

        -- Cleanup stale entries
        selectedIndex = cleanupStalePairs(pendingPairs, selectedIndex)
    end

    print("")
    print("[*] Timed out")
    EventUtils.sleep(1)
    return false
end

return AddComputer
