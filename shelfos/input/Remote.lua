-- Remote.lua
-- Remote input relay for pocket computer integration

local Protocol = mpm('net/Protocol')

local Remote = {}
Remote.__index = Remote

-- Create a new remote input handler
-- @param channel Network channel
function Remote.new(channel)
    local self = setmetatable({}, Remote)
    self.channel = channel
    self.pendingRequests = {}
    self.requestTimeout = 60000  -- 1 minute

    return self
end

-- Request text input from a pocket computer
-- @param targetId Pocket computer ID (nil = broadcast)
-- @param field Field name
-- @param fieldType Field type
-- @param currentValue Current value
-- @param constraints Validation constraints
-- @return request ID
function Remote:requestInput(targetId, field, fieldType, currentValue, constraints)
    local requestId = string.format("%d_%d", os.getComputerID(), os.epoch("utc"))

    local msg = Protocol.createInputRequest(field, fieldType, currentValue, constraints)
    msg.requestId = requestId

    if targetId then
        self.channel:send(targetId, msg)
    else
        self.channel:broadcast(msg)
    end

    self.pendingRequests[requestId] = {
        field = field,
        timestamp = os.epoch("utc"),
        callback = nil
    }

    return requestId
end

-- Wait for input response
-- @param requestId Request ID
-- @param timeout Timeout in seconds
-- @return value, cancelled (boolean)
function Remote:waitForResponse(requestId, timeout)
    timeout = timeout or 60

    local deadline = os.epoch("utc") + (timeout * 1000)

    while os.epoch("utc") < deadline do
        local senderId, msg = self.channel:receive(1)

        if msg and msg.type == Protocol.MessageType.INPUT_RESPONSE then
            if msg.requestId == requestId then
                self.pendingRequests[requestId] = nil
                return msg.data.value, false
            end
        elseif msg and msg.type == Protocol.MessageType.INPUT_CANCEL then
            if msg.requestId == requestId then
                self.pendingRequests[requestId] = nil
                return nil, true
            end
        end
    end

    -- Timeout
    self.pendingRequests[requestId] = nil
    return nil, true
end

-- Request input with callback (non-blocking)
-- @param targetId Pocket computer ID
-- @param field Field name
-- @param fieldType Field type
-- @param currentValue Current value
-- @param constraints Validation constraints
-- @param callback Function(value, cancelled)
function Remote:requestInputAsync(targetId, field, fieldType, currentValue, constraints, callback)
    local requestId = self:requestInput(targetId, field, fieldType, currentValue, constraints)
    self.pendingRequests[requestId].callback = callback
end

-- Process incoming messages (call in event loop)
function Remote:processMessage(senderId, msg)
    if msg.type == Protocol.MessageType.INPUT_RESPONSE then
        local request = self.pendingRequests[msg.requestId]
        if request and request.callback then
            request.callback(msg.data.value, false)
            self.pendingRequests[msg.requestId] = nil
            return true
        end
    elseif msg.type == Protocol.MessageType.INPUT_CANCEL then
        local request = self.pendingRequests[msg.requestId]
        if request and request.callback then
            request.callback(nil, true)
            self.pendingRequests[msg.requestId] = nil
            return true
        end
    end

    return false
end

-- Clean up expired requests
function Remote:cleanup()
    local now = os.epoch("utc")

    for id, request in pairs(self.pendingRequests) do
        if now - request.timestamp > self.requestTimeout then
            if request.callback then
                request.callback(nil, true)
            end
            self.pendingRequests[id] = nil
        end
    end
end

-- Check if there are pending requests
function Remote:hasPendingRequests()
    for _ in pairs(self.pendingRequests) do
        return true
    end
    return false
end

return Remote
