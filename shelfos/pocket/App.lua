-- App.lua
-- Pocket computer companion application

local Channel = mpm('net/Channel')
local Crypto = mpm('net/Crypto')
local Protocol = mpm('net/Protocol')
local Discovery = mpm('net/Discovery')
local Pairing = mpm('net/Pairing')
local Notifications = mpm('shelfos/pocket/Notifications')
local EventUtils = mpm('utils/EventUtils')

local App = {}
App.__index = App

-- Create new pocket app
function App.new()
    local self = setmetatable({}, App)
    self.channel = nil
    self.discovery = nil
    self.notifications = Notifications.new()
    self.running = false
    self.selectedZone = nil
    self.hasSecret = false
    self.modemType = nil

    return self
end

-- Initialize basic modem (no crypto)
function App:initModem()
    local modem = peripheral.find("modem")
    if not modem then
        return false, nil
    end

    local modemName = peripheral.getName(modem)
    self.modemType = modem.isWireless() and "wireless" or "wired"

    -- Open for rednet (needed for pairing protocol)
    rednet.open(modemName)

    return true, self.modemType
end

-- Initialize full networking (with crypto)
function App:initNetwork(secret)
    Crypto.setSecret(secret)
    self.hasSecret = true

    -- Open channel for encrypted communication
    self.channel = Channel.new()
    local ok, modemType = self.channel:open(true)

    if not ok then
        return false
    end

    -- Set up discovery
    self.discovery = Discovery.new(self.channel)
    self.discovery:setIdentity("pocket_" .. os.getComputerID(), "Pocket")
    self.discovery:start()

    -- Register message handlers
    self:registerHandlers()

    return true
end

-- Load secret from file
function App:loadSecret()
    local secretPath = "/shelfos_secret.txt"

    if fs.exists(secretPath) then
        local file = fs.open(secretPath, "r")
        if file then
            local secret = file.readAll()
            file.close()
            if secret and #secret >= 16 then
                return secret
            end
        end
    end

    return nil
end

-- Save secret to file
function App:saveSecret(secret)
    local secretPath = "/shelfos_secret.txt"
    local file = fs.open(secretPath, "w")
    if file then
        file.write(secret)
        file.close()
        return true
    end
    return false
end

-- Initialize the app
function App:init()
    term.clear()
    term.setCursorPos(1, 1)
    print("ShelfOS Pocket")
    print("==============")
    print("")

    -- Check modem first
    local ok, modemType = self:initModem()
    if not ok then
        print("[!] No modem found")
        print("Attach wireless/ender")
        return false
    end
    print("[*] " .. modemType .. " modem")

    -- Try to load existing secret
    local secret = self:loadSecret()
    if secret then
        print("[*] Swarm configured")
        self:initNetwork(secret)
    else
        print("[!] Not in swarm")
        print("")
        print("Select 'Join Swarm' to")
        print("connect to existing zone")
    end

    return true
end

-- Register message handlers
function App:registerHandlers()
    -- Input requests from zones
    self.channel:on(Protocol.MessageType.INPUT_REQUEST, function(senderId, msg)
        self:handleInputRequest(senderId, msg)
    end)

    -- Alerts from zones
    self.channel:on(Protocol.MessageType.ALERT, function(senderId, msg)
        self:handleAlert(senderId, msg)
    end)

    -- Zone announcements
    self.channel:on(Protocol.MessageType.ANNOUNCE, function(senderId, msg)
        -- Discovery handles this
    end)
end

-- Handle input request
function App:handleInputRequest(senderId, msg)
    self.notifications:notify("Input Request", msg.data.field)

    term.clear()
    term.setCursorPos(1, 1)

    print("=== Input Requested ===")
    print("")
    print("Field: " .. (msg.data.field or "unknown"))
    print("Type: " .. (msg.data.fieldType or "string"))
    print("Current: " .. tostring(msg.data.currentValue or ""))
    print("")

    if msg.data.constraints then
        if msg.data.constraints.min then
            print("Min: " .. msg.data.constraints.min)
        end
        if msg.data.constraints.max then
            print("Max: " .. msg.data.constraints.max)
        end
    end

    print("")
    print("Enter new value (or 'cancel'):")
    write("> ")

    local input = read()

    local response
    if input == "cancel" or input == "" then
        response = Protocol.createMessage(Protocol.MessageType.INPUT_CANCEL, {}, msg.requestId)
    else
        -- Validate based on type
        local value = input
        if msg.data.fieldType == "number" then
            value = tonumber(input)
            if not value then
                print("[!] Invalid number")
                response = Protocol.createMessage(Protocol.MessageType.INPUT_CANCEL, {}, msg.requestId)
            end
        end

        if not response then
            response = Protocol.createInputResponse(msg, value)
        end
    end

    self.channel:send(senderId, response)

    print("")
    print("[*] Response sent")
    sleep(1)

    self:showMainMenu()
end

-- Handle alert
function App:handleAlert(senderId, msg)
    local data = msg.data or {}
    self.notifications:add(data.level or "info", data.title or "Alert", data.message or "")

    -- Show notification briefly
    local oldX, oldY = term.getCursorPos()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.orange)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" [!] " .. (data.title or "Alert"):sub(1, 20))
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.setCursorPos(oldX, oldY)

    -- Send acknowledgment
    local ack = Protocol.createMessage(Protocol.MessageType.ALERT_ACK, {}, msg.requestId)
    self.channel:send(senderId, ack)
end

-- Show main menu
function App:showMainMenu()
    term.clear()
    term.setCursorPos(1, 1)

    print("=== ShelfOS Pocket ===")
    print("")

    if self.hasSecret then
        -- Full menu when in swarm
        print("1. Discover Zones")
        print("2. Add Computer")
        print("3. Notifications (" .. self.notifications:count() .. ")")
        print("4. Leave Swarm")
        print("5. Exit")
    else
        -- Limited menu when not paired
        print("1. Join Swarm")
        print("2. Create Swarm")
        print("3. Exit")
        print("")
        print("(Join existing zone")
        print(" or create new swarm)")
    end

    print("")
    write("Select: ")
end

-- Join an existing swarm by pairing with a zone
function App:joinSwarm()
    term.clear()
    term.setCursorPos(1, 1)

    print("=== Join Swarm ===")
    print("")
    print("Enter pairing code")
    print("from zone computer:")
    print("")
    write("> ")

    local code = read():upper():gsub("%s", "")

    if #code < 4 then
        print("")
        print("[!] Code too short")
        EventUtils.sleep(2)
        return
    end

    print("")
    print("Searching for zone...")

    -- Use rednet.lookup to find ShelfOS hosts
    local peerIds = {rednet.lookup("shelfos")}

    if #peerIds == 0 then
        print("[!] No zones found")
        print("Ensure zone is running")
        EventUtils.sleep(2)
        return
    end

    -- Try to pair with each zone using the code
    local PAIR_PROTOCOL = "shelfos_pair"

    for _, peerId in ipairs(peerIds) do
        local request = {
            type = "pair_request",
            code = code
        }

        rednet.send(peerId, request, PAIR_PROTOCOL)
    end

    -- Wait for response
    local deadline = os.epoch("utc") + 5000

    while os.epoch("utc") < deadline do
        local timer = os.startTimer(0.5)
        local event, p1, p2, p3 = os.pullEvent()

        if event == "rednet_message" then
            local senderId = p1
            local response = p2
            local msgProtocol = p3

            if msgProtocol == PAIR_PROTOCOL and type(response) == "table" then
                if response.type == "pair_response" and response.success then
                    -- Got the secret!
                    if response.secret and #response.secret >= 16 then
                        self:saveSecret(response.secret)
                        self:initNetwork(response.secret)

                        -- Save pairing code for future use
                        local configPath = "/shelfos_pocket.config"
                        local config = {
                            pairingCode = response.pairingCode or code,
                            zoneId = response.zoneId,
                            zoneName = response.zoneName
                        }
                        local file = fs.open(configPath, "w")
                        if file then
                            file.write(textutils.serialize(config))
                            file.close()
                        end

                        print("")
                        print("[*] Joined swarm!")
                        print("Zone: " .. (response.zoneName or "Unknown"))
                        EventUtils.sleep(2)
                        return
                    end
                elseif response.type == "pair_response" and not response.success then
                    print("")
                    print("[!] Wrong code")
                    EventUtils.sleep(2)
                    return
                end
            end
        end
    end

    print("")
    print("[!] No response")
    print("Check code & retry")
    EventUtils.sleep(2)
end

-- Create a new swarm (this pocket becomes controller)
function App:createSwarm()
    term.clear()
    term.setCursorPos(1, 1)

    print("=== Create Swarm ===")
    print("")

    -- Generate new secret using Pairing module
    local secret = Pairing.generateSecret()
    local pairingCode = Pairing.generateCode()

    -- Save secret
    self:saveSecret(secret)
    self:initNetwork(secret)

    -- Save config
    local configPath = "/shelfos_pocket.config"
    local config = {
        pairingCode = pairingCode,
        isController = true
    }
    local file = fs.open(configPath, "w")
    if file then
        file.write(textutils.serialize(config))
        file.close()
    end

    print("[*] Swarm created!")
    print("")
    print("Pairing code:")
    print("  " .. pairingCode)
    print("")
    print("Use 'Add Computer'")
    print("to add zones.")
    print("")
    print("Press any key...")
    EventUtils.pullEvent("key")
end

-- Leave the current swarm
function App:leaveSwarm()
    term.clear()
    term.setCursorPos(1, 1)

    print("=== Leave Swarm ===")
    print("")
    print("Are you sure?")
    print("")
    print("Y = Yes, leave")
    print("N = Cancel")

    while true do
        local event, key = EventUtils.pullEvent("key")
        if key == keys.y then
            -- Clear credentials
            fs.delete("/shelfos_secret.txt")
            fs.delete("/shelfos_pocket.config")

            -- Reset state
            if self.channel then
                self.channel:close()
                self.channel = nil
            end
            self.discovery = nil
            self.hasSecret = false

            print("")
            print("[*] Left swarm")
            EventUtils.sleep(1)
            return
        elseif key == keys.n then
            return
        end
    end
end

-- Discover zones
function App:discoverZones()
    term.clear()
    term.setCursorPos(1, 1)

    print("Discovering zones...")
    print("")

    local zones = self.discovery:discover(3)

    if #zones == 0 then
        print("No zones found")
        print("")
        print("Make sure zone computers are running")
        print("and using the same secret.")
    else
        print("Found " .. #zones .. " zone(s):")
        print("")

        for i, zone in ipairs(zones) do
            print(i .. ". " .. zone.zoneName)
            print("   ID: " .. zone.zoneId)
            print("   Computer: #" .. zone.computerId)
            if zone.monitors and #zone.monitors > 0 then
                print("   Monitors: " .. #zone.monitors)
            end
            print("")
        end
    end

    print("")
    print("Press any key...")
    EventUtils.pullEvent("key")
end

-- View notifications
function App:viewNotifications()
    term.clear()
    term.setCursorPos(1, 1)

    local notes = self.notifications:getAll()

    if #notes == 0 then
        print("No notifications")
    else
        print("=== Notifications ===")
        print("")

        for i, note in ipairs(notes) do
            local levelColor = colors.white
            if note.level == "warning" then
                levelColor = colors.orange
            elseif note.level == "error" then
                levelColor = colors.red
            elseif note.level == "critical" then
                levelColor = colors.red
            end

            term.setTextColor(levelColor)
            print("[" .. note.level:upper() .. "] " .. note.title)
            term.setTextColor(colors.lightGray)
            print("  " .. note.message:sub(1, 30))
            term.setTextColor(colors.white)
        end
    end

    print("")
    print("C to clear, any other key to return")

    local event, key = EventUtils.pullEvent("key")
    if key == keys.c then
        self.notifications:clear()
    end
end

-- Add a computer to the swarm via pocket pairing
function App:addComputerToSwarm()
    local PAIR_PROTOCOL = "shelfos_pair"

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

    -- Get the secret from our config
    local secretPath = "/shelfos_secret.txt"
    local secret = nil

    if fs.exists(secretPath) then
        local file = fs.open(secretPath, "r")
        if file then
            secret = file.readAll()
            file.close()
        end
    end

    if not secret then
        print("[!] No swarm secret configured")
        print("    Configure pocket first")
        EventUtils.sleep(2)
        return
    end

    -- Load pairing code from pocket config if exists
    local pairingCode = nil
    local zoneId = nil
    local zoneName = "Swarm"

    local configPath = "/shelfos_pocket.config"
    if fs.exists(configPath) then
        local file = fs.open(configPath, "r")
        if file then
            local content = file.readAll()
            file.close()
            local ok, config = pcall(textutils.unserialize, content)
            if ok and config then
                pairingCode = config.pairingCode
                zoneId = config.zoneId
                zoneName = config.zoneName or zoneName
            end
        end
    end

    -- If no pairing code, generate one for the swarm
    if not pairingCode then
        pairingCode = Pairing.generateCode()

        -- Save it
        local config = { pairingCode = pairingCode, zoneId = zoneId, zoneName = zoneName }
        local file = fs.open(configPath, "w")
        if file then
            file.write(textutils.serialize(config))
            file.close()
        end
    end

    -- Ensure modem is open for the pairing protocol
    local modem = peripheral.find("modem")
    if not modem then
        print("[!] No modem found")
        EventUtils.sleep(2)
        return
    end

    local modemName = peripheral.getName(modem)
    rednet.open(modemName)

    -- Track pending pair requests
    local pendingPairs = {}
    local selectedIndex = 0
    local lastRefresh = 0

    -- Listen for PAIR_READY messages
    local timeout = 30  -- seconds
    local deadline = os.epoch("utc") + (timeout * 1000)

    while os.epoch("utc") < deadline do
        -- Refresh display
        local now = os.epoch("utc")
        if now - lastRefresh > 500 then
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
                print("[Enter] Pair  [Up/Down] Select")
            end

            print("")
            local remaining = math.ceil((deadline - now) / 1000)
            print("[Q] Cancel (" .. remaining .. "s)")

            lastRefresh = now
        end

        -- Wait for events
        local timer = os.startTimer(0.3)
        local event, p1, p2, p3 = os.pullEvent()

        if event == "rednet_message" then
            local senderId = p1
            local message = p2
            local msgProtocol = p3

            if msgProtocol == PAIR_PROTOCOL and type(message) == "table" then
                if message.type == Protocol.MessageType.PAIR_READY then
                    -- Add to pending list (or update existing)
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
                        table.insert(pendingPairs, {
                            senderId = senderId,
                            token = message.data.token,
                            label = message.data.label or ("Computer #" .. senderId),
                            timestamp = os.epoch("utc")
                        })
                        -- Auto-select first one
                        if selectedIndex == 0 then
                            selectedIndex = 1
                        end
                    end

                    lastRefresh = 0  -- Force refresh

                elseif message.type == Protocol.MessageType.PAIR_COMPLETE then
                    -- Pairing confirmed
                    print("")
                    print("[*] " .. (message.data and message.data.label or "Computer") .. " joined swarm!")
                    EventUtils.sleep(2)
                    return
                end
            end

        elseif event == "key" then
            if p1 == keys.q then
                -- Cancel
                return

            elseif p1 == keys.up then
                if selectedIndex > 1 then
                    selectedIndex = selectedIndex - 1
                    lastRefresh = 0
                end

            elseif p1 == keys.down then
                if selectedIndex < #pendingPairs then
                    selectedIndex = selectedIndex + 1
                    lastRefresh = 0
                end

            elseif p1 == keys.enter and selectedIndex > 0 and selectedIndex <= #pendingPairs then
                -- Send pairing secret to selected computer
                local pair = pendingPairs[selectedIndex]

                print("")
                print("[*] Sending swarm secret to " .. pair.label .. "...")

                local deliverMsg = Protocol.createPairDeliver(
                    pair.token,
                    secret,
                    pairingCode,
                    zoneId,
                    zoneName
                )

                rednet.send(pair.senderId, deliverMsg, PAIR_PROTOCOL)

                -- Wait for confirmation
                local confirmDeadline = os.epoch("utc") + 5000
                while os.epoch("utc") < confirmDeadline do
                    local cTimer = os.startTimer(0.5)
                    local cEvent, cp1, cp2, cp3 = os.pullEvent()

                    if cEvent == "rednet_message" and cp1 == pair.senderId then
                        if cp3 == PAIR_PROTOCOL and type(cp2) == "table" then
                            if cp2.type == Protocol.MessageType.PAIR_COMPLETE then
                                print("[*] " .. pair.label .. " joined swarm!")
                                EventUtils.sleep(2)
                                return
                            end
                        end
                    end
                end

                print("[!] No confirmation received")
                EventUtils.sleep(1)
                -- Remove from pending list
                table.remove(pendingPairs, selectedIndex)
                if selectedIndex > #pendingPairs then
                    selectedIndex = #pendingPairs
                end
                lastRefresh = 0
            end
        end

        -- Clean up old entries (older than 15 seconds)
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

    print("")
    print("[*] Timed out")
    EventUtils.sleep(1)
end

-- Main run loop
function App:run()
    if not self:init() then
        return
    end

    self.running = true
    print("")
    print("Press any key...")
    EventUtils.pullEvent("key")

    while self.running do
        self:showMainMenu()

        -- Wait for input
        local event, p1 = os.pullEvent()

        if event == "char" then
            if self.hasSecret then
                -- Full menu when in swarm
                if p1 == "1" then
                    self:discoverZones()
                elseif p1 == "2" then
                    self:addComputerToSwarm()
                elseif p1 == "3" then
                    self:viewNotifications()
                elseif p1 == "4" then
                    self:leaveSwarm()
                elseif p1 == "5" then
                    self.running = false
                end
            else
                -- Limited menu when not paired
                if p1 == "1" then
                    self:joinSwarm()
                elseif p1 == "2" then
                    self:createSwarm()
                elseif p1 == "3" then
                    self.running = false
                end
            end
        end

        -- Process any pending network messages (if connected)
        if self.channel then
            self.channel:poll(0)
        end
    end

    -- Cleanup
    if self.channel then
        self.channel:close()
    end

    term.clear()
    term.setCursorPos(1, 1)
    print("Goodbye!")
end

return App
