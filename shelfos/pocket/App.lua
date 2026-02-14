-- App.lua
-- Pocket computer companion application
--
-- SECURITY: Pairing uses display-only codes
-- The code shown on the zone's screen is never broadcast
-- User must enter it on the pocket for secure secret delivery

local Channel = mpm('net/Channel')
local Crypto = mpm('net/Crypto')
local Protocol = mpm('net/Protocol')
local Discovery = mpm('net/Discovery')
local Pairing = mpm('net/Pairing')
local Paths = mpm('shelfos/core/Paths')
local Notifications = mpm('shelfos/pocket/Notifications')
local EventUtils = mpm('utils/EventUtils')
local AddComputerScreen = mpm('shelfos/pocket/screens/AddComputer')
local SwarmStatusScreen = mpm('shelfos/pocket/screens/SwarmStatus')

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
-- If secret is nil, clears crypto state (for when leaving swarm)
function App:initNetwork(secret)
    if not secret then
        Crypto.clearSecret()
        self.hasSecret = false
        return false
    end
    Crypto.setSecret(secret)
    self.hasSecret = true

    -- Open channel for encrypted communication
    self.channel = Channel.new()
    local ok, modemType = self.channel:open(true)

    if not ok then
        return false
    end

    -- Register with CC:Tweaked native service discovery
    -- This allows zones to find us via rednet.lookup("shelfos")
    rednet.host("shelfos", "pocket_" .. os.getComputerID())

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
    if fs.exists(Paths.POCKET_SECRET) then
        local file = fs.open(Paths.POCKET_SECRET, "r")
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
    local file = fs.open(Paths.POCKET_SECRET, "w")
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

    -- Clear any stale crypto state from previous session FIRST
    -- _G persists across program restarts in CC:Tweaked
    Crypto.clearSecret()

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
        -- Clear any stale crypto state from previous session
        -- _G persists across program restarts in CC:Tweaked
        Crypto.clearSecret()
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

                        -- Save config
                        local config = {
                            zoneId = response.zoneId,
                            zoneName = response.zoneName
                        }
                        local file = fs.open(Paths.POCKET_CONFIG, "w")
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

    -- Save secret
    self:saveSecret(secret)
    self:initNetwork(secret)

    -- Save config
    local config = {
        isController = true
    }
    local file = fs.open(Paths.POCKET_CONFIG, "w")
    if file then
        file.write(textutils.serialize(config))
        file.close()
    end

    print("[*] Swarm created!")
    print("")
    print("Use 'Add Computer'")
    print("to add zones to swarm.")
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
            -- LEAVE SWARM: Clear all credentials and reboot

            -- 1. Close network
            if self.channel then
                self.channel:close()
            end
            rednet.unhost("shelfos")

            -- 2. Clear crypto state
            Crypto.clearSecret()

            -- 3. Delete all pocket files
            Paths.deletePocketFiles()

            -- 4. Show message and reboot
            term.clear()
            term.setCursorPos(1, 1)
            print("=====================================")
            print("   LEFT SWARM")
            print("=====================================")
            print("")
            print("Credentials cleared.")
            print("Rebooting in 2 seconds...")

            sleep(2)
            os.reboot()
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
        print("Make sure zone computers are")
        print("paired and in the swarm.")
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
-- Delegates to screens/AddComputer for the UI flow
function App:addComputerToSwarm()
    AddComputerScreen.run()
end

-- Process a network message directly (without polling, to avoid event loss)
-- @param senderId Sender computer ID
-- @param envelope Raw message envelope
-- @param msgProtocol Protocol name
function App:processNetworkMessage(senderId, envelope, msgProtocol)
    -- Only process our protocol
    if msgProtocol ~= self.channel.protocol then
        return
    end

    -- Unwrap crypto
    local message
    if Crypto.hasSecret() then
        local data, err = Crypto.unwrap(envelope)
        if not data then
            return  -- Invalid signature, ignore
        end
        message = data
    else
        message = envelope
    end

    -- Validate message
    local valid, err = Protocol.validate(message)
    if not valid then
        return
    end

    -- Call handler if registered
    local handler = self.channel.handlers[message.type]
    if handler then
        pcall(handler, senderId, message, self.channel)
    end
end

-- Show setup menu (when not in swarm)
function App:showSetupMenu()
    term.clear()
    term.setCursorPos(1, 1)

    print("=== ShelfOS Pocket ===")
    print("")
    print("Not connected to swarm")
    print("")
    print("1. Join Swarm")
    print("2. Create Swarm")
    print("3. Exit")
    print("")
    write("Select: ")
end

-- Run setup flow (when not in swarm)
-- @return true if joined/created swarm, false if exited
function App:runSetupFlow()
    while true do
        self:showSetupMenu()

        local event, p1 = os.pullEvent()

        if event == "char" then
            if p1 == "1" then
                self:joinSwarm()
                -- Check if we now have a secret
                local secret = self:loadSecret()
                if secret then
                    self:initNetwork(secret)
                    return true
                end
            elseif p1 == "2" then
                self:createSwarm()
                -- Check if we now have a secret
                local secret = self:loadSecret()
                if secret then
                    self:initNetwork(secret)
                    return true
                end
            elseif p1 == "3" then
                return false
            end
        end
    end
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

    -- If not in swarm, run setup flow first
    if not self.hasSecret then
        if not self:runSetupFlow() then
            -- User chose to exit
            term.clear()
            term.setCursorPos(1, 1)
            print("Goodbye!")
            return
        end
    end

    -- Main loop - SwarmStatus is the default view
    while self.running do
        -- Run SwarmStatus as the main view
        local action = SwarmStatusScreen.run(self.discovery, nil, nil)

        if action == "quit" then
            self.running = false

        elseif action == "add" then
            self:addComputerToSwarm()

        elseif action == "notifications" then
            self:viewNotifications()

        elseif action == "leave" then
            self:leaveSwarm()
            -- If we left the swarm, go back to setup
            if not self:loadSecret() then
                if not self:runSetupFlow() then
                    self.running = false
                end
            end
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
