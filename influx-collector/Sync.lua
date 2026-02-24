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

-- Request config from any peer on the network.
-- Returns the config table on success, or nil on timeout/no modem.
function Sync.requestConfig(timeoutSeconds)
    if not openModem() then
        markStatus("no_modem")
        return nil
    end

    rednet.broadcast({ type = "config_request" }, Sync.PROTOCOL)
    Sync.state.lastRequestAt = nowMs()
    markStatus("request_sent")

    local timeout = tonumber(timeoutSeconds) or 5
    local _, payload = rednet.receive(Sync.PROTOCOL, timeout)

    if type(payload) == "table" and payload.type == "config_response" then
        Sync.state.lastResponseAt = nowMs()
        markStatus("received")
        return payload.config
    end

    markStatus("timeout")
    return nil
end

-- Respond to config requests from peers while the collector is running.
-- Runs forever; intended to be called inside parallel.waitForAll.
function Sync.respondLoop(config)
    if not openModem() then
        Sync.state.enabled = false
        markStatus("no_modem")
        return
    end

    Sync.state.enabled = true
    markStatus("listening")

    while true do
        local senderId, payload = rednet.receive(Sync.PROTOCOL)
        if type(payload) == "table" and payload.type == "config_request" then
            Sync.state.lastRequestAt = nowMs()
            rednet.send(senderId, {
                type = "config_response",
                config = {
                    url         = config.url,
                    org         = config.org,
                    bucket      = config.bucket,
                    token       = config.share_token and config.token or nil,
                    share_token = config.share_token == true
                }
            }, Sync.PROTOCOL)
            Sync.state.lastResponseAt = nowMs()
            markStatus("responded")
        end
    end
end

return Sync
