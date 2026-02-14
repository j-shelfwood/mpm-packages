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
-- @param preferWireless Prefer wireless/ender modem over wired (default: true)
-- @return success, modemType ("wireless", "wired", or nil)
function Channel:open(preferWireless)
    -- CC:Tweaked: ALL modems are type "modem", distinguish via isWireless()
    local modems = {peripheral.find("modem")}

    local wired = nil
    local wireless = nil

    for _, m in ipairs(modems) do
        if m.isWireless() then
            wireless = m  -- Could be wireless OR ender (both return isWireless=true)
        else
            wired = m
        end
    end

    -- Select modem based on preference
    -- Default prefers wireless/ender for unlimited range
    if preferWireless ~= false and wireless then
        self.modem = wireless
    elseif wired then
        self.modem = wired
    elseif wireless then
        self.modem = wireless
    end

    if not self.modem then
        return false, nil
    end

    self.modemName = peripheral.getName(self.modem)

    -- CRITICAL: Close ALL other modems to prevent duplicate message reception
    -- If multiple modems are open, broadcasts are received on each, causing
    -- duplicate nonce errors when the same envelope is unwrapped twice
    for _, m in ipairs(modems) do
        local name = peripheral.getName(m)
        if name ~= self.modemName and rednet.isOpen(name) then
            rednet.close(name)
        end
    end

    rednet.open(self.modemName)
    self.opened = true

    local modemType = self.modem.isWireless() and "wireless" or "wired"
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
            return nil, nil  -- Silent fail for invalid/replayed messages
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
