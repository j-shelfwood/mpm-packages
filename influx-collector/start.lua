local Config = mpm('influx-collector/Config')
local Discovery = mpm('influx-collector/Discovery')
local Influx = mpm('influx-collector/Influx')
local Poller = mpm('influx-collector/Poller')

if not http then
    error("HTTP API not available. Enable http in CC:Tweaked config.")
end

local config = Config.ensure()
if not config.token or config.token == "" then
    error("InfluxDB token missing. Edit /influx-collector.config and add token.")
end

local influx = Influx.new(config)
local discovery = Discovery.new()
local poller = Poller.new(config, influx, discovery)

print("Influx collector running for node: " .. config.node)
print("Endpoint: " .. config.url)

poller:run()
