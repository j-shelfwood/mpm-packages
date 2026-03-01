local Config = mpm('influx-collector/Config')
local Discovery = mpm('influx-collector/Discovery')
local Dashboard = mpm('influx-collector/Dashboard')
local Influx = mpm('influx-collector/Influx')
local Poller = mpm('influx-collector/Poller')
local Sync = mpm('influx-collector/Sync')

if not http then
    error("HTTP API not available. Enable http in CC:Tweaked config.")
end

local config, meta = Config.loadMerged()
if not config.token or config.token == "" then
    local synced = Sync.requestConfig(5)
    if synced then
        synced.node = config.node or synced.node
        synced.share_token = config.share_token or synced.share_token
        Config.saveEnv(synced)
        config = synced
    end
end

config = Config.ensure()
if not config.token or config.token == "" then
    error("InfluxDB token missing. Edit /influx-collector.env and add token.")
end

local influx = Influx.new(config)
local discovery = Discovery.new()
local poller = Poller.new(config, influx, discovery)
local dashboard = Dashboard.new(config, influx, poller)
poller:setEventSink(function(kind, data)
    pcall(os.queueEvent, "collector_event", { kind = kind, data = data })
end)

print("Influx collector running for node: " .. config.node)
print("Endpoint: " .. config.url)

parallel.waitForAll(function()
    poller:run()
end, function()
    dashboard:run()
end, function()
    Sync.respondLoop(config)
end)
