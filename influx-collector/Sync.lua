local ModemUtils = mpm('utils/ModemUtils')

local Sync = {}
Sync.PROTOCOL = "influx_collector_sync"
Sync.state = {
    enabled = false,
    lastRequestAt = 0,
    lastResponseAt = 0,
    lastStatus = "idle"
}

local function nowMs()
    return os.epoch("utc")
end

local function openModem()
    if not rednet then
        return false
    end
    local ok, _, _ = ModemUtils.open(true)
    return ok == true
end

local function markStatus(status)
    Sync.state.lastStatus = status
    pcall(os.queueEvent, "collector_event", { kind = "config_sync", status = status })
end

function Sync.getStatus()
    return Sync.state
end

function Sync.requestConfig(timeoutSeconds)
    if not openModem() then
        markStatus("no_modem")
        return nil
    end

    local nonce = tostring(nowMs()) .. "-" .. tostring(math.random(1000, 9999))
    local message = {
        type = "config_request",
        nonce = nonce,
        sender = os.getComputerID(),
        want_token = true
    }

    rednet.broadcast(message, Sync.PROTOCOL)
    Sync.state.lastRequestAt = nowMs()
    markStatus("request_sent")

    local timeout = tonumber(timeoutSeconds) or 5
    local deadline = nowMs() + (timeout * 1000)

    while nowMs() < deadline do
        local event = { os.pullEvent() }
        if event[1] == "rednet_message" and event[4] == Sync.PROTOCOL then
            local payload = event[3]
            if type(payload) == "table" and payload.type == "config_response" and payload.nonce == nonce then
                Sync.state.lastResponseAt = nowMs()
                markStatus("received")
                return payload.config
            end
        else
            os.queueEvent(table.unpack(event))
        end
    end

    markStatus("timeout")
    return nil
end

function Sync.respondLoop(config)
    if not openModem() then
        Sync.state.enabled = false
        markStatus("no_modem")
        return
    end

    Sync.state.enabled = true
    markStatus("listening")

    while true do
        local event = { os.pullEventRaw() }
        if event[1] == "terminate" then
            error("Terminated", 0)
        end

        if event[1] == "rednet_message" and event[4] == Sync.PROTOCOL then
            local senderId = event[2]
            local payload = event[3]
            if type(payload) == "table" and payload.type == "config_request" then
                Sync.state.lastRequestAt = nowMs()
                local response = {
                    type = "config_response",
                    nonce = payload.nonce,
                    config = {
                        url = config.url,
                        org = config.org,
                        bucket = config.bucket,
                        token = config.share_token and config.token or nil,
                        share_token = config.share_token == true
                    }
                }
                rednet.send(senderId, response, Sync.PROTOCOL)
                Sync.state.lastResponseAt = nowMs()
                markStatus("responded")
            end
        else
            os.queueEvent(table.unpack(event))
            sleep(0)
        end
    end
end

return Sync
