-- Channel.lua
-- Rednet channel abstraction with automatic crypto wrapping

local Crypto = mpm('net/Crypto')
local Protocol = mpm('net/Protocol')
local Yield = mpm('utils/Yield')
local ModemUtils = mpm('utils/ModemUtils')

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
-- @param preferEnder Prefer ender modem over wired (default: true)
-- @return success, modemType ("ender", "wired", or nil)
function Channel:open(preferEnder)
    -- Use ModemUtils for consistent modem selection across all modules
    -- ModemUtils.open() also handles closing other modems to prevent duplicate reception
    local ok, modemName, modemType = ModemUtils.open(preferEnder)

    if not ok then
        return false, nil
    end

    self.modem = peripheral.wrap(modemName)
    self.modemName = modemName
    self.opened = true

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
-- @param message Message table (MUST have crypto secret set)
-- @return success
function Channel:send(targetId, message)
    if not self.opened then
        return false
    end

    -- SECURITY: Channel requires crypto for swarm communication
    -- Plaintext transmission is a security violation
    if not Crypto.hasSecret() then
        error("SECURITY: Channel.send() called without swarm secret. Initialize network first.")
    end

    local envelope = Crypto.wrap(message)
    return rednet.send(targetId, envelope, self.protocol)
end

-- Broadcast a message
-- @param message Message table (MUST have crypto secret set)
function Channel:broadcast(message)
    if not self.opened then
        return false
    end

    -- SECURITY: Channel requires crypto for swarm communication
    -- Plaintext transmission is a security violation
    if not Crypto.hasSecret() then
        error("SECURITY: Channel.broadcast() called without swarm secret. Initialize network first.")
    end

    local envelope = Crypto.wrap(message)
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

    -- SECURITY: Channel requires crypto for swarm communication
    if not Crypto.hasSecret() then
        return nil, nil  -- Silently ignore - we shouldn't be receiving without secret
    end

    local senderId, envelope = rednet.receive(self.protocol, timeout)

    if not senderId then
        return nil, nil
    end

    -- Unwrap and verify crypto signature
    local data, err = Crypto.unwrap(envelope)
    if not data then
        return nil, nil  -- Silent fail for invalid/replayed messages
    end

    return senderId, data
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
