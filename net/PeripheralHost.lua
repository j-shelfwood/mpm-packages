-- PeripheralHost.lua
-- Serves local peripherals to remote computers over ender modem
-- Replicates wired modem's peripheral sharing behavior

local Protocol = mpm('net/Protocol')
local MachineActivity = mpm('peripherals/MachineActivity')

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

local DEFAULT_CHUNK_LIMIT = 200
local MAX_CHUNK_LIMIT = 1000
local SNAPSHOT_TTL_MS = 5000
local ACTIVITY_POLL_INTERVAL_MS = 1500

-- Fields to keep from ME Bridge resource lists
-- Everything else (tags, components, fingerprint, maxStackSize, fluidType) is stripped
local KEEP_FIELDS = {
    name = true,
    displayName = true,
    count = true,
    amount = true,
    isCraftable = true,
}

local function simpleHash(str)
    local h = 5381
    for i = 1, #str do
        h = ((h * 33) + string.byte(str, i)) % 4294967296
    end
    return string.format("%08x", h)
end

local function subscriptionKey(peripheralName, methodName, args)
    local ok, encoded = pcall(textutils.serialize, args or {})
    return table.concat({
        tostring(peripheralName or ""),
        tostring(methodName or ""),
        ok and encoded or ""
    }, "|")
end

local function hashResults(results)
    if type(results) ~= "table" then
        return tostring(results)
    end
    local ok, encoded = pcall(textutils.serialize, results)
    if ok and encoded then
        return encoded
    end
    return tostring(results)
end

local function hashResourceRows(items)
    if type(items) ~= "table" then
        return nil
    end

    local rows = {}
    for i, item in ipairs(items) do
        if type(item) == "table" then
            rows[i] = table.concat({
                tostring(item.name or ""),
                tostring(item.displayName or ""),
                tostring(item.count or 0),
                tostring(item.amount or 0),
                tostring(item.isCraftable and 1 or 0)
            }, "|")
        else
            rows[i] = tostring(item)
        end
    end
    table.sort(rows)
    return simpleHash(table.concat(rows, "\n"))
end

local function computePeripheralStateHash(peripherals)
    local chunks = {}
    local names = {}
    for name in pairs(peripherals) do
        table.insert(names, name)
    end
    table.sort(names)

    for _, name in ipairs(names) do
        local info = peripherals[name]
        local methodList = {}
        if info and type(info.methods) == "table" then
            for i = 1, #info.methods do
                methodList[i] = tostring(info.methods[i])
            end
            table.sort(methodList)
        end
        table.insert(chunks, tostring(name))
        table.insert(chunks, tostring(info and info.type or ""))
        table.insert(chunks, table.concat(methodList, ","))
    end

    return simpleHash(table.concat(chunks, "|"))
end

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

local function sliceList(items, offset, limit)
    if type(items) ~= "table" then
        return items
    end
    local total = #items
    local safeOffset = math.max(0, math.floor(tonumber(offset) or 0))
    local safeLimit = math.max(1, math.floor(tonumber(limit) or DEFAULT_CHUNK_LIMIT))
    safeLimit = math.min(safeLimit, MAX_CHUNK_LIMIT)
    local endIndex = math.min(total, safeOffset + safeLimit)
    local chunk = {}
    for i = safeOffset + 1, endIndex do
        chunk[#chunk + 1] = items[i]
    end
    return chunk, total, safeOffset, safeLimit, endIndex >= total
end

local function cleanupSnapshots(self, now)
    if not self.snapshots then
        return
    end
    for queryId, snapshot in pairs(self.snapshots) do
        if not snapshot or (snapshot.expiresAt or 0) <= now then
            self.snapshots[queryId] = nil
        end
    end
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
    self.stateHash = ""
    self.activityListener = nil
    self.subscriptions = {} -- { clientId -> { [key] = sub } }
    self.clients = {}
    self.snapshots = {}
    self.lastActivityPollAt = 0

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

local function snapshotKey(peripheralName, methodName, args)
    return subscriptionKey(peripheralName, methodName, args)
end

local function makeSnapshotId()
    return string.format("snap_%d_%d", os.epoch("utc"), math.random(1000, 9999))
end

local function buildActivitySummary(info)
    if not info or not info.peripheral or not MachineActivity then
        return nil
    end
    if not MachineActivity.supportsActivity(info.peripheral) then
        return nil
    end
    local active, data = MachineActivity.getActivity(info.peripheral)
    return {
        active = active and true or false,
        data = data or {}
    }
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

            local info = {
                name = name,
                type = pType,
                methods = methods,
                peripheral = p
            }
            info.activity = buildActivitySummary(info)
            if info.activity then
                info.activityHash = hashResults({ info.activity.active, info.activity.data })
            end
            self.peripherals[name] = info
        end
    end

    self.stateHash = computePeripheralStateHash(self.peripherals)

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
            methods = info.methods,
            activity = info.activity
        })
    end
    return list
end

-- Announce available peripherals (broadcast)
function PeripheralHost:announce()
    if not self.channel then return false end

    local activity = {}
    for name, info in pairs(self.peripherals) do
        if info.activity then
            activity[name] = info.activity
        end
    end

    local msg = Protocol.createPeriphAnnounce(self.computerId, self.computerName, {
        stateHash = self.stateHash,
        peripheralCount = self:getPeripheralCount(),
        activity = next(activity) and activity or nil
    })

    self.channel:broadcast(msg)
    self:emitActivity("announce", {
        peripheralCount = msg.data.peripheralCount or 0,
        stateHash = msg.data.stateHash
    })
    return true
end

-- Handle peripheral discovery request
-- @param senderId Requesting computer ID
-- @param msg The discover message
function PeripheralHost:handleDiscover(senderId, msg)
    self.clients[senderId] = true
    local peripherals = self:getPeripheralList()
    local response = Protocol.createPeriphList(msg, peripherals, self.computerId, self.computerName)
    self.channel:send(senderId, response)
    self:emitActivity("discover", {
        senderId = senderId,
        peripheralCount = #peripherals
    })
end

local function sendCallError(self, senderId, msg, peripheralName, methodName, detail, activityError, durationMs)
    local errResponse = Protocol.createPeriphError(msg, detail)
    self.channel:send(senderId, errResponse)
    self:emitActivity("call_error", {
        senderId = senderId,
        peripheral = peripheralName,
        method = methodName,
        error = activityError,
        durationMs = durationMs
    })
end

local function methodExists(info, methodName)
    if not info or type(info.methods) ~= "table" then
        return false
    end
    for _, m in ipairs(info.methods) do
        if m == methodName then
            return true
        end
    end
    return false
end

function PeripheralHost:handleSubscribe(senderId, msg)
    self.clients[senderId] = true
    local peripheralName = msg.data.peripheral
    local methodName = msg.data.method
    local args = msg.data.args or {}
    local intervalMs = msg.data.intervalMs
    local eventName = msg.data.event

    local info = self.peripherals[peripheralName]
    if not info then
        self.channel:send(senderId, Protocol.createError(msg, "Peripheral not found: " .. tostring(peripheralName)))
        return
    end

    if not methodExists(info, methodName) then
        self.channel:send(senderId, Protocol.createError(msg, "Method not found: " .. tostring(methodName)))
        return
    end

    local key = subscriptionKey(peripheralName, methodName, args)
    self.subscriptions[senderId] = self.subscriptions[senderId] or {}
    self.subscriptions[senderId][key] = {
        key = key,
        peripheral = peripheralName,
        method = methodName,
        args = args,
        intervalMs = intervalMs or 1000,
        event = eventName,
        nextAt = 0,
        lastHash = nil
    }

    self.channel:send(senderId, Protocol.createResponse(msg, Protocol.MessageType.OK, {
        subscribed = true
    }))
end

function PeripheralHost:handleUnsubscribe(senderId, msg)
    local peripheralName = msg.data.peripheral
    local methodName = msg.data.method
    local args = msg.data.args or {}
    local key = subscriptionKey(peripheralName, methodName, args)
    if self.subscriptions[senderId] then
        self.subscriptions[senderId][key] = nil
    end
    self.channel:send(senderId, Protocol.createResponse(msg, Protocol.MessageType.OK, {
        unsubscribed = true
    }))
end

function PeripheralHost:pollSubscriptions()
    if not self.channel then return end
    local now = os.epoch("utc")

    for clientId, subs in pairs(self.subscriptions) do
        for _, sub in pairs(subs) do
            if now >= (sub.nextAt or 0) then
                sub.nextAt = now + (sub.intervalMs or 1000)
                local info = self.peripherals[sub.peripheral]
                if info then
                    local p = info.peripheral
                    local method = p and p[sub.method]
                    if method then
                        local results = {pcall(method, table.unpack(sub.args or {}))}
                        local ok = table.remove(results, 1)
                        if ok then
                            local resultHash = nil
                            if STRIP_METHODS[sub.method] and results[1] and type(results[1]) == "table" then
                                results[1] = stripResourceList(results[1])
                                resultHash = hashResourceRows(results[1])
                            else
                                resultHash = hashResults(results)
                            end

                            if resultHash ~= sub.lastHash then
                                sub.lastHash = resultHash
                                local payload = {
                                    peripheral = sub.peripheral,
                                    method = sub.method,
                                    args = sub.args,
                                    results = results,
                                    meta = {
                                        resultHash = resultHash
                                    },
                                    event = sub.event,
                                    hostId = self.computerId
                                }
                                self.channel:send(clientId, Protocol.createPeriphStatePush(payload))
                            end
                        end
                    end
                end
            end
        end
    end
end

function PeripheralHost:pollActivitySnapshots()
    if not self.channel then return end
    local now = os.epoch("utc")
    if now - (self.lastActivityPollAt or 0) < ACTIVITY_POLL_INTERVAL_MS then
        return
    end
    self.lastActivityPollAt = now

    if not next(self.clients or {}) then
        return
    end

    for name, info in pairs(self.peripherals) do
        local activity = buildActivitySummary(info)
        if activity then
            local hash = hashResults({ activity.active, activity.data })
            if hash ~= info.activityHash then
                info.activityHash = hash
                info.activity = activity
                local payload = {
                    peripheral = name,
                    method = "activity",
                    results = { activity.active, activity.data },
                    meta = { activity = true },
                    hostId = self.computerId
                }
                for clientId in pairs(self.clients) do
                    self.channel:send(clientId, Protocol.createPeriphStatePush(payload))
                end
            end
        end
    end
end

-- Handle peripheral method call
-- @param senderId Requesting computer ID
-- @param msg The call message
function PeripheralHost:handleCall(senderId, msg)
    local startedAt = os.epoch("utc")
    local peripheralName = msg.data.peripheral
    local methodName = msg.data.method
    local args = msg.data.args or {}
    local options = msg.data.options or {}
    local now = os.epoch("utc")
    cleanupSnapshots(self, now)

    -- Find the peripheral
    local info = self.peripherals[peripheralName]
    if not info then
        sendCallError(self, senderId, msg, peripheralName, methodName, "Peripheral not found: " .. peripheralName, "Peripheral not found")
        return
    end

    -- Check method exists
    if not methodExists(info, methodName) then
        sendCallError(self, senderId, msg, peripheralName, methodName, "Method not found: " .. methodName, "Method not found")
        return
    end

    -- Call the method
    local p = info.peripheral
    local method = p[methodName]

    if not method then
        sendCallError(self, senderId, msg, peripheralName, methodName, "Method unavailable: " .. methodName, "Method unavailable")
        return
    end

    local results = nil
    local success = false
    local usingSnapshot = false
    local snapshotId = type(options.queryId) == "string" and options.queryId or nil
    local argsKey = snapshotKey(peripheralName, methodName, args)
    local snapshot = nil

    if STRIP_METHODS[methodName] and snapshotId then
        local cached = self.snapshots[snapshotId]
        if cached
            and cached.peripheral == peripheralName
            and cached.method == methodName
            and cached.argsKey == argsKey
            and (cached.expiresAt or 0) > now then
            snapshot = cached
            snapshot.expiresAt = now + SNAPSHOT_TTL_MS
            results = { snapshot.items }
            success = true
            usingSnapshot = true
        elseif (options.offset or 0) > 0 then
            sendCallError(self, senderId, msg, peripheralName, methodName, "snapshot_expired", "snapshot_expired")
            return
        end
    elseif STRIP_METHODS[methodName] and (options.offset or 0) > 0 then
        sendCallError(self, senderId, msg, peripheralName, methodName, "snapshot_required", "snapshot_required")
        return
    end

    if not usingSnapshot then
        -- Execute with pcall for safety
        results = {pcall(method, table.unpack(args))}
        success = table.remove(results, 1)
    end

    if success then
        local resultHash = nil
        -- Strip bulky fields from large resource lists to prevent RPC timeouts
        -- ME Bridge getItems/getFluids/etc return tags, components, fingerprint per item
        -- which inflates serialization size 10-100x beyond what consumers need
        local responseResults = results
        if STRIP_METHODS[methodName] and results[1] and type(results[1]) == "table" then
            local stripped = results[1]
            if not usingSnapshot then
                stripped = stripResourceList(results[1])
                results[1] = stripped
            end
            resultHash = snapshot and snapshot.resultHash or hashResourceRows(stripped)

            local offset = options.offset or 0
            local limit = options.limit or DEFAULT_CHUNK_LIMIT
            local chunk, total, safeOffset, safeLimit, done = sliceList(stripped, offset, limit)
            responseResults = results
            responseResults[1] = chunk

            if type(options.resultHash) == "string"
                and options.resultHash == resultHash
                and not options.page
                and (not options.offset or options.offset == 0) then
                responseResults = nil
            end

            local queryId = snapshotId
            if not queryId and not done then
                queryId = makeSnapshotId()
                self.snapshots[queryId] = {
                    items = stripped,
                    resultHash = resultHash,
                    peripheral = peripheralName,
                    method = methodName,
                    argsKey = argsKey,
                    expiresAt = now + SNAPSHOT_TTL_MS
                }
            end

            local response = Protocol.createPeriphResult(msg, responseResults)
            response.data.meta = {
                resultHash = resultHash,
                unchanged = responseResults == nil,
                chunked = true,
                total = total,
                offset = safeOffset,
                limit = safeLimit,
                done = done,
                queryId = queryId
            }
            self.channel:send(senderId, response)
        else
            if resultHash and type(options.resultHash) == "string" and options.resultHash == resultHash then
                responseResults = nil
            end
            local response = Protocol.createPeriphResult(msg, responseResults)
            if resultHash then
                response.data.meta = {
                    resultHash = resultHash,
                    unchanged = responseResults == nil
                }
            end
            self.channel:send(senderId, response)
        end
        self:emitActivity("call", {
            senderId = senderId,
            peripheral = peripheralName,
            method = methodName,
            durationMs = os.epoch("utc") - startedAt
        })
    else
        local errorMessage = results[1] or "Unknown error"
        sendCallError(
            self,
            senderId,
            msg,
            peripheralName,
            methodName,
            errorMessage,
            errorMessage,
            os.epoch("utc") - startedAt
        )
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

    self.channel:on(Protocol.MessageType.PERIPH_SUBSCRIBE, function(senderId, msg)
        self:handleSubscribe(senderId, msg)
    end)

    self.channel:on(Protocol.MessageType.PERIPH_UNSUBSCRIBE, function(senderId, msg)
        self:handleUnsubscribe(senderId, msg)
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
    local oldHash = self.stateHash
    local newCount = self:scan()

    -- Announce when shared peripheral state changes
    if newCount ~= oldCount or self.stateHash ~= oldHash then
        self:announce()
    end

    self:emitActivity("rescan", {
        oldCount = oldCount,
        newCount = newCount,
        changed = (newCount ~= oldCount) or (self.stateHash ~= oldHash)
    })

    return newCount
end

return PeripheralHost
