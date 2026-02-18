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

-- Methods that return large lists of resources from ME Bridge
-- Their results contain bulky fields (tags, components, fingerprint, etc.)
-- that are not needed by remote consumers and cause RPC timeouts
local STRIP_METHODS = {
    getItems = true,
    getFluids = true,
    getChemicals = true,
    getCraftableItems = true,
    getCraftableFluids = true,
    getCraftableChemicals = true,
}

-- Fields to keep from ME Bridge resource lists
-- Everything else (tags, components, fingerprint, maxStackSize, fluidType) is stripped
local KEEP_FIELDS = {
    name = true,
    displayName = true,
    count = true,
    amount = true,
    isCraftable = true,
}

-- Strip bulky fields from a resource list to reduce serialization size
-- @param items Array of resource tables from ME Bridge
-- @return Stripped array with only essential fields
local function stripResourceList(items)
    if type(items) ~= "table" then return items end

    local stripped = {}
    for i, item in ipairs(items) do
        if type(item) == "table" then
            local slim = {}
            for key, value in pairs(item) do
                if KEEP_FIELDS[key] then
                    slim[key] = value
                end
            end
            stripped[i] = slim
        else
            stripped[i] = item
        end
    end
    return stripped
end

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
    self.activityListener = nil

    return self
end

-- Set activity listener for telemetry hooks
-- @param listener Function(activity, data)
function PeripheralHost:setActivityListener(listener)
    if type(listener) == "function" then
        self.activityListener = listener
    else
        self.activityListener = nil
    end
end

-- Emit host activity event (best-effort, non-fatal)
function PeripheralHost:emitActivity(activity, data)
    if not self.activityListener then return end
    pcall(self.activityListener, activity, data or {})
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

    self:emitActivity("scan", {
        peripheralCount = self:getPeripheralCount()
    })

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
    self:emitActivity("announce", {
        peripheralCount = #msg.data.peripherals
    })
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
    local peripherals = self:getPeripheralList()
    local response = Protocol.createPeriphList(msg, peripherals)
    self.channel:send(senderId, response)
    self:emitActivity("discover", {
        senderId = senderId,
        peripheralCount = #peripherals
    })
end

-- Handle peripheral method call
-- @param senderId Requesting computer ID
-- @param msg The call message
function PeripheralHost:handleCall(senderId, msg)
    local startedAt = os.epoch("utc")
    local peripheralName = msg.data.peripheral
    local methodName = msg.data.method
    local args = msg.data.args or {}

    -- Find the peripheral
    local info = self.peripherals[peripheralName]
    if not info then
        local errResponse = Protocol.createPeriphError(msg, "Peripheral not found: " .. peripheralName)
        self.channel:send(senderId, errResponse)
        self:emitActivity("call_error", {
            senderId = senderId,
            peripheral = peripheralName,
            method = methodName,
            error = "Peripheral not found"
        })
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
        self:emitActivity("call_error", {
            senderId = senderId,
            peripheral = peripheralName,
            method = methodName,
            error = "Method not found"
        })
        return
    end

    -- Call the method
    local p = info.peripheral
    local method = p[methodName]

    if not method then
        local errResponse = Protocol.createPeriphError(msg, "Method unavailable: " .. methodName)
        self.channel:send(senderId, errResponse)
        self:emitActivity("call_error", {
            senderId = senderId,
            peripheral = peripheralName,
            method = methodName,
            error = "Method unavailable"
        })
        return
    end

    -- Execute with pcall for safety
    local results = {pcall(method, table.unpack(args))}
    local success = table.remove(results, 1)

    if success then
        -- Strip bulky fields from large resource lists to prevent RPC timeouts
        -- ME Bridge getItems/getFluids/etc return tags, components, fingerprint per item
        -- which inflates serialization size 10-100x beyond what consumers need
        if STRIP_METHODS[methodName] and results[1] and type(results[1]) == "table" then
            results[1] = stripResourceList(results[1])
        end

        local response = Protocol.createPeriphResult(msg, results)
        self.channel:send(senderId, response)
        self:emitActivity("call", {
            senderId = senderId,
            peripheral = peripheralName,
            method = methodName,
            durationMs = os.epoch("utc") - startedAt
        })
    else
        local errResponse = Protocol.createPeriphError(msg, results[1] or "Unknown error")
        self.channel:send(senderId, errResponse)
        self:emitActivity("call_error", {
            senderId = senderId,
            peripheral = peripheralName,
            method = methodName,
            error = results[1] or "Unknown error",
            durationMs = os.epoch("utc") - startedAt
        })
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
    self:emitActivity("start", {
        peripheralCount = self:getPeripheralCount()
    })
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

    self:emitActivity("rescan", {
        oldCount = oldCount,
        newCount = newCount,
        changed = newCount ~= oldCount
    })

    return newCount
end

return PeripheralHost
