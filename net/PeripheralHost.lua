-- PeripheralHost.lua
-- Serves local peripherals to remote computers over ender modem
-- Replicates wired modem's peripheral sharing behavior

local Protocol = mpm('net/Protocol')

local PeripheralHost = {}
PeripheralHost.__index = PeripheralHost

-- Peripheral types to EXCLUDE from sharing (blacklist)
-- We share everything except monitors, modems, and computers
local EXCLUDED_TYPES = {
    "monitor",
    "modem",
    "computer",
    "turtle",
    "pocket"
}

-- Create a new peripheral host
-- @param channel Channel instance for network communication
-- @param computerId Computer identifier
-- @param computerName Computer name
function PeripheralHost.new(channel, computerId, computerName)
    local self = setmetatable({}, PeripheralHost)

    self.channel = channel
    self.computerId = computerId
    self.computerName = computerName
    self.peripherals = {}  -- {name -> {type, methods, peripheral}}
    self.lastAnnounce = 0
    self.announceInterval = 10000  -- 10 seconds

    return self
end

-- Check if a peripheral type should be shared
-- We share everything except excluded types (monitors, modems, computers)
local function isShareable(peripheralType)
    for _, t in ipairs(EXCLUDED_TYPES) do
        if peripheralType == t then
            return false
        end
    end
    return true
end

-- Scan for local peripherals to share
function PeripheralHost:scan()
    self.peripherals = {}

    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        local pType = peripheral.getType(name)

        if isShareable(pType) then
            local methods = peripheral.getMethods(name)
            local p = peripheral.wrap(name)

            self.peripherals[name] = {
                name = name,
                type = pType,
                methods = methods,
                peripheral = p
            }
        end
    end

    return self:getPeripheralCount()
end

-- Get count of shared peripherals
function PeripheralHost:getPeripheralCount()
    local count = 0
    for _ in pairs(self.peripherals) do
        count = count + 1
    end
    return count
end

-- Get peripheral info list (for announcements)
function PeripheralHost:getPeripheralList()
    local list = {}
    for name, info in pairs(self.peripherals) do
        table.insert(list, {
            name = name,
            type = info.type,
            methods = info.methods
        })
    end
    return list
end

-- Announce available peripherals (broadcast)
function PeripheralHost:announce()
    if not self.channel then return false end

    local msg = Protocol.createPeriphAnnounce(
        self.computerId,
        self.computerName,
        self:getPeripheralList()
    )

    self.channel:broadcast(msg)
    self.lastAnnounce = os.epoch("utc")
    return true
end

-- Check if should re-announce
function PeripheralHost:shouldAnnounce()
    return os.epoch("utc") - self.lastAnnounce > self.announceInterval
end

-- Handle peripheral discovery request
-- @param senderId Requesting computer ID
-- @param msg The discover message
function PeripheralHost:handleDiscover(senderId, msg)
    print("[PeripheralHost] Discovery request from #" .. senderId)
    local peripherals = self:getPeripheralList()
    print("[PeripheralHost] Responding with " .. #peripherals .. " peripheral(s)")
    local response = Protocol.createPeriphList(msg, peripherals)
    self.channel:send(senderId, response)
end

-- Handle peripheral method call
-- @param senderId Requesting computer ID
-- @param msg The call message
function PeripheralHost:handleCall(senderId, msg)
    local peripheralName = msg.data.peripheral
    local methodName = msg.data.method
    local args = msg.data.args or {}

    -- Find the peripheral
    local info = self.peripherals[peripheralName]
    if not info then
        local errResponse = Protocol.createPeriphError(msg, "Peripheral not found: " .. peripheralName)
        self.channel:send(senderId, errResponse)
        return
    end

    -- Check method exists
    local methodExists = false
    for _, m in ipairs(info.methods) do
        if m == methodName then
            methodExists = true
            break
        end
    end

    if not methodExists then
        local errResponse = Protocol.createPeriphError(msg, "Method not found: " .. methodName)
        self.channel:send(senderId, errResponse)
        return
    end

    -- Call the method
    local p = info.peripheral
    local method = p[methodName]

    if not method then
        local errResponse = Protocol.createPeriphError(msg, "Method unavailable: " .. methodName)
        self.channel:send(senderId, errResponse)
        return
    end

    -- Execute with pcall for safety
    local results = {pcall(method, table.unpack(args))}
    local success = table.remove(results, 1)

    if success then
        local response = Protocol.createPeriphResult(msg, results)
        self.channel:send(senderId, response)
    else
        local errResponse = Protocol.createPeriphError(msg, results[1] or "Unknown error")
        self.channel:send(senderId, errResponse)
    end
end

-- Register handlers with channel
function PeripheralHost:registerHandlers()
    if not self.channel then return end

    self.channel:on(Protocol.MessageType.PERIPH_DISCOVER, function(senderId, msg)
        self:handleDiscover(senderId, msg)
    end)

    self.channel:on(Protocol.MessageType.PERIPH_CALL, function(senderId, msg)
        self:handleCall(senderId, msg)
    end)
end

-- Start hosting (scan + register + announce)
function PeripheralHost:start()
    self:scan()
    self:registerHandlers()
    self:announce()
    return self:getPeripheralCount()
end

-- Rescan peripherals (call when peripheral_attach/detach)
function PeripheralHost:rescan()
    local oldCount = self:getPeripheralCount()
    local newCount = self:scan()

    -- Announce if changed
    if newCount ~= oldCount then
        self:announce()
    end

    return newCount
end

return PeripheralHost
