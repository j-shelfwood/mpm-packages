-- App.lua
-- Pocket computer companion application

local Channel = mpm('net/Channel')
local Crypto = mpm('net/Crypto')
local Protocol = mpm('net/Protocol')
local Discovery = mpm('net/Discovery')
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

    return self
end

-- Initialize the app
function App:init()
    print("ShelfOS Pocket Companion")
    print("========================")
    print("")

    -- Load or create secret
    local secretPath = "/shelfos_secret.txt"
    local secret = nil

    if fs.exists(secretPath) then
        local file = fs.open(secretPath, "r")
        secret = file.readAll()
        file.close()
        print("[*] Loaded secret from file")
    else
        print("[!] No secret configured")
        print("    Enter the shared secret from your zone computer:")
        write("> ")
        secret = read()

        if #secret < 16 then
            print("[!] Secret too short (min 16 chars)")
            return false
        end

        local file = fs.open(secretPath, "w")
        file.write(secret)
        file.close()
        print("[*] Secret saved")
    end

    Crypto.setSecret(secret)

    -- Open network
    self.channel = Channel.new()
    local ok, modemType = self.channel:open(true)

    if not ok then
        print("[!] No wireless modem found")
        print("    Attach a wireless or ender modem")
        return false
    end

    print("[*] Network: " .. modemType .. " modem")

    -- Set up discovery
    self.discovery = Discovery.new(self.channel)
    self.discovery:setIdentity("pocket_" .. os.getComputerID(), "Pocket")
    self.discovery:start()

    -- Register message handlers
    self:registerHandlers()

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
    print("1. Discover Zones")
    print("2. View Notifications (" .. self.notifications:count() .. ")")
    print("3. Zone Status")
    print("4. Settings")
    print("5. Exit")
    print("")
    write("Select: ")
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

-- Main run loop
function App:run()
    if not self:init() then
        return
    end

    self.running = true
    print("")
    print("Press any key to continue...")
    EventUtils.pullEvent("key")

    while self.running do
        self:showMainMenu()

        -- Wait for input or network event
        local event, p1 = os.pullEvent()

        if event == "char" then
            if p1 == "1" then
                self:discoverZones()
            elseif p1 == "2" then
                self:viewNotifications()
            elseif p1 == "3" then
                -- Zone status (TODO)
                print("")
                print("Not implemented yet")
                sleep(1)
            elseif p1 == "4" then
                -- Settings (TODO)
                print("")
                print("Not implemented yet")
                sleep(1)
            elseif p1 == "5" then
                self.running = false
            end
        end

        -- Process any pending network messages
        self.channel:poll(0)
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
