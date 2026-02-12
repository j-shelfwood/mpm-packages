-- Channel.lua
-- Rednet channel abstraction with automatic crypto wrapping

local Crypto = mpm('net/Crypto')
local Protocol = mpm('net/Protocol')
local Yield = mpm('utils/Yield')

local Channel = {}
Channel.__index = Channel

-- Create a new channel
-- @param protocol Protocol name (default: "shelfos")
-- @return Channel instance
function Channel.new(protocol)
    local self = setmetatable({}, Channel)
    self.protocol = protocol or Protocol.PROTOCOL
    self.modem = nil
    self.modemName = nil
    self.opened = false
    self.handlers = {}
    self.responseWaiters = {}

    return self
end

-- Open the channel (find and open modem)
-- @param preferEnder Prefer ender modem over wireless
-- @return success, modemType ("ender", "wireless", or nil)
function Channel:open(preferEnder)
    -- Try to find modem
    local ender = peripheral.find("ender_modem")
    local wireless = peripheral.find("wireless_modem")

    if preferEnder and ender then
        self.modem = ender
    elseif wireless then
        self.modem = wireless
    elseif ender then
        self.modem = ender
    end

    if not self.modem then
        return false, nil
    end

    self.modemName = peripheral.getName(self.modem)
    rednet.open(self.modemName)
    self.opened = true

    local modemType = ender and self.modem == ender and "ender" or "wireless"
    return true, modemType
end

-- Close the channel
function Channel:close()
    if self.opened and self.modemName then
        rednet.close(self.modemName)
        self.opened = false
    end
end

-- Check if channel is open
function Channel:isOpen()
    return self.opened
end

-- Send a message to a specific computer
-- @param targetId Target computer ID
-- @param message Message table (will be wrapped with crypto if secret set)
-- @return success
function Channel:send(targetId, message)
    if not self.opened then
        return false
    end

    local envelope
    if Crypto.hasSecret() then
        envelope = Crypto.wrap(message)
    else
        envelope = message
    end

    return rednet.send(targetId, envelope, self.protocol)
end

-- Broadcast a message
-- @param message Message table
function Channel:broadcast(message)
    if not self.opened then
        return false
    end

    local envelope
    if Crypto.hasSecret() then
        envelope = Crypto.wrap(message)
    else
        envelope = message
    end

    rednet.broadcast(envelope, self.protocol)
    return true
end

-- Send and wait for response
-- @param targetId Target computer ID
-- @param message Request message
-- @param timeout Timeout in seconds
-- @return response message or nil, error
function Channel:request(targetId, message, timeout)
    timeout = timeout or 5

    -- Generate request ID if not present
    if not message.requestId then
        message.requestId = string.format("%d_%d", os.getComputerID(), os.epoch("utc"))
    end

    if not self:send(targetId, message) then
        return nil, "Failed to send"
    end

    -- Wait for response with matching requestId (with yields)
    local deadline = os.epoch("utc") + (timeout * 1000)

    while os.epoch("utc") < deadline do
        local senderId, response = self:receive((deadline - os.epoch("utc")) / 1000)

        if response and response.requestId == message.requestId then
            return response, nil
        end
        Yield.yield()
    end

    return nil, "Timeout"
end

-- Receive a message
-- @param timeout Timeout in seconds
-- @return senderId, message (or nil, nil on timeout/error)
function Channel:receive(timeout)
    if not self.opened then
        return nil, nil
    end

    local senderId, envelope = rednet.receive(self.protocol, timeout)

    if not senderId then
        return nil, nil
    end

    -- Unwrap crypto if secret is set
    local message
    if Crypto.hasSecret() then
        local data, err = Crypto.unwrap(envelope)
        if not data then
            -- Log but don't expose error details
            return nil, nil
        end
        message = data
    else
        message = envelope
    end

    return senderId, message
end

-- Register a message handler
-- @param msgType Message type to handle
-- @param handler Function(senderId, message, channel)
function Channel:on(msgType, handler)
    self.handlers[msgType] = handler
end

-- Remove a message handler
function Channel:off(msgType)
    self.handlers[msgType] = nil
end

-- Process incoming messages (call in event loop)
-- @param timeout How long to wait for messages
-- @return true if message was handled
function Channel:poll(timeout)
    local senderId, message = self:receive(timeout or 0)

    if message then
        -- Validate message
        local valid, err = Protocol.validate(message)
        if not valid then
            return false
        end

        -- Call handler if registered
        local handler = self.handlers[message.type]
        if handler then
            local ok, result = pcall(handler, senderId, message, self)
            return ok
        end
    end

    return false
end

-- Run message loop (blocking)
-- @param onIdle Function to call when no messages (receives elapsed time)
function Channel:run(onIdle)
    local lastActivity = os.epoch("utc")

    while true do
        local handled = self:poll(0.5)

        if handled then
            lastActivity = os.epoch("utc")
        elseif onIdle then
            onIdle(os.epoch("utc") - lastActivity)
        end
    end
end

return Channel
