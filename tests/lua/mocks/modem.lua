-- Mock Ender Modem Peripheral
-- Simulates CC:Tweaked modem behavior for testing

local Modem = {}
Modem.__index = Modem

function Modem.new(config)
    config = config or {}
    local self = setmetatable({}, Modem)

    self.name = config.name or "back"
    self.wireless = config.wireless ~= false  -- default true (ender modem)
    self.open_channels = {}
    self.transmit_log = {}
    self.receive_queue = {}

    return self
end

-- CC:Tweaked modem methods
function Modem:isWireless()
    return self.wireless
end

function Modem:open(channel)
    self.open_channels[channel] = true
end

function Modem:close(channel)
    self.open_channels[channel] = nil
end

function Modem:isOpen(channel)
    return self.open_channels[channel] == true
end

function Modem:closeAll()
    self.open_channels = {}
end

function Modem:transmit(channel, replyChannel, message)
    table.insert(self.transmit_log, {
        channel = channel,
        replyChannel = replyChannel,
        message = message,
        timestamp = os.epoch and os.epoch("utc") or 0
    })
end

-- Test helpers
function Modem:getTransmitLog()
    return self.transmit_log
end

function Modem:clearTransmitLog()
    self.transmit_log = {}
end

function Modem:queueReceive(channel, replyChannel, message, distance)
    table.insert(self.receive_queue, {
        channel = channel,
        replyChannel = replyChannel,
        message = message,
        distance = distance or 0
    })
end

function Modem:popReceive()
    return table.remove(self.receive_queue, 1)
end

return Modem
