-- Mock Rednet API
-- Simulates CC:Tweaked rednet for testing

local Rednet = {}

-- State
local open_modems = {}
local hosts = {}  -- protocol -> {hostname -> id}
local message_queue = {}
local broadcast_log = {}
local send_log = {}

function Rednet.reset()
    open_modems = {}
    hosts = {}
    message_queue = {}
    broadcast_log = {}
    send_log = {}
end

-- Get the peripheral mock module
local function get_peripheral()
    return _G.peripheral
end

-- CC:Tweaked rednet API
function Rednet.open(modem_name)
    local p = get_peripheral()
    if not p then
        error("peripheral API not available")
    end

    if not p.isPresent(modem_name) then
        error("No such modem: " .. modem_name, 2)
    end

    local modem_type = p.getType(modem_name)
    if modem_type ~= "modem" then
        error("Not a modem: " .. modem_name, 2)
    end

    open_modems[modem_name] = true
end

function Rednet.close(modem_name)
    if modem_name then
        open_modems[modem_name] = nil
    else
        open_modems = {}
    end
end

function Rednet.isOpen(modem_name)
    if modem_name then
        return open_modems[modem_name] == true
    else
        for _ in pairs(open_modems) do
            return true
        end
        return false
    end
end

function Rednet.send(recipient, message, protocol)
    if not Rednet.isOpen() then
        error("No open modem", 2)
    end

    table.insert(send_log, {
        recipient = recipient,
        message = message,
        protocol = protocol,
        timestamp = os.epoch and os.epoch("utc") or 0
    })

    return true
end

function Rednet.broadcast(message, protocol)
    if not Rednet.isOpen() then
        error("No open modem", 2)
    end

    table.insert(broadcast_log, {
        message = message,
        protocol = protocol,
        timestamp = os.epoch and os.epoch("utc") or 0
    })

    return true
end

function Rednet.receive(protocol_filter, timeout)
    -- Check queue for matching message
    for i, msg in ipairs(message_queue) do
        if not protocol_filter or msg.protocol == protocol_filter then
            table.remove(message_queue, i)
            return msg.sender, msg.message, msg.protocol
        end
    end

    -- No message available
    return nil
end

function Rednet.host(protocol, hostname)
    hosts[protocol] = hosts[protocol] or {}
    hosts[protocol][hostname] = os.getComputerID and os.getComputerID() or 42
end

function Rednet.unhost(protocol)
    if protocol then
        hosts[protocol] = nil
    end
end

function Rednet.lookup(protocol, hostname)
    if not hosts[protocol] then
        return nil
    end

    if hostname then
        return hosts[protocol][hostname]
    else
        -- Return all hosts for protocol
        local result = {}
        for _, id in pairs(hosts[protocol]) do
            table.insert(result, id)
        end
        return result
    end
end

function Rednet.run()
    -- No-op for testing
end

-- Test helpers
function Rednet.queueMessage(sender, message, protocol)
    table.insert(message_queue, {
        sender = sender,
        message = message,
        protocol = protocol
    })
end

function Rednet.getBroadcastLog()
    return broadcast_log
end

function Rednet.getSendLog()
    return send_log
end

function Rednet.clearLogs()
    broadcast_log = {}
    send_log = {}
end

function Rednet.getOpenModems()
    local result = {}
    for name in pairs(open_modems) do
        table.insert(result, name)
    end
    return result
end

-- Install into global _G.rednet
function Rednet.install()
    _G.rednet = {
        open = Rednet.open,
        close = Rednet.close,
        isOpen = Rednet.isOpen,
        send = Rednet.send,
        broadcast = Rednet.broadcast,
        receive = Rednet.receive,
        host = Rednet.host,
        unhost = Rednet.unhost,
        lookup = Rednet.lookup,
        run = Rednet.run,
        -- Test helpers exposed for convenience
        _queueMessage = Rednet.queueMessage,
        _getBroadcastLog = Rednet.getBroadcastLog,
        _getSendLog = Rednet.getSendLog,
        _clearLogs = Rednet.clearLogs
    }
end

return Rednet
