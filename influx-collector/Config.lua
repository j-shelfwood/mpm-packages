local Config = {}

local CONFIG_PATH = "/influx-collector.config"
local ENV_PATH = "/influx-collector.env"
local SETTINGS_PREFIX = "influx.collector."

local function defaultNode()
    local label = os.getComputerLabel()
    if label and label ~= "" then
        return label
    end
    return "cc-" .. tostring(os.getComputerID())
end

local DEFAULTS = {
    url = "https://influx.shelfwood.co",
    org = "shelfwood",
    bucket = "mc",
    token = "",
    node = defaultNode(),
    machine_interval_s = 5,
    energy_interval_s = 5,
    energy_detector_interval_s = 5,
    ae_interval_s = 60,
    ae_slow_interval_s = 600,
    ae_slow_threshold_ms = 5000,
    ae_top_items = 20,
    ae_top_fluids = 10,
    flush_interval_s = 5,
    max_buffer_lines = 5000
}

local function normalizeUrl(url)
    if not url or url == "" then return url end
    return url:gsub("/+$", "")
end

local function merge(base, overrides)
    if type(overrides) ~= "table" then
        return base
    end
    for key, value in pairs(overrides) do
        if value ~= nil and value ~= "" then
            base[key] = value
        end
    end
    return base
end

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parseEnvValue(value)
    value = trim(value or "")
    if value:sub(1, 1) == "\"" and value:sub(-1) == "\"" then
        return value:sub(2, -2)
    end
    if value:sub(1, 1) == "'" and value:sub(-1) == "'" then
        return value:sub(2, -2)
    end
    return value
end

local function envKey(key)
    return (key or ""):upper()
end

function Config.loadFile()
    if not fs.exists(CONFIG_PATH) then
        return nil
    end
    local handle = fs.open(CONFIG_PATH, "r")
    if not handle then
        return nil
    end
    local content = handle.readAll()
    handle.close()
    local data = textutils.unserialize(content)
    if type(data) ~= "table" then
        return nil
    end
    data.url = normalizeUrl(data.url or DEFAULTS.url)
    data.node = data.node or defaultNode()
    return data
end

function Config.saveFile(config)
    local handle = fs.open(CONFIG_PATH, "w")
    if not handle then
        error("Failed to write " .. CONFIG_PATH)
    end
    handle.write(textutils.serialize(config))
    handle.close()
end

function Config.loadEnv()
    if not fs.exists(ENV_PATH) then
        return nil
    end
    local handle = fs.open(ENV_PATH, "r")
    if not handle then
        return nil
    end
    local raw = handle.readAll()
    handle.close()

    local data = {}
    for line in raw:gmatch("[^\r\n]+") do
        if not line:match("^%s*#") and not line:match("^%s*$") then
            local key, value = line:match("^%s*([^=]+)%s*=%s*(.*)$")
            if key then
                key = envKey(trim(key))
                value = parseEnvValue(value)
                if key == "INFLUX_URL" then data.url = value end
                if key == "INFLUX_ORG" then data.org = value end
                if key == "INFLUX_BUCKET" then data.bucket = value end
                if key == "INFLUX_TOKEN" then data.token = value end
                if key == "INFLUX_NODE" then data.node = value end
            end
        end
    end

    data.url = normalizeUrl(data.url or DEFAULTS.url)
    data.node = data.node or defaultNode()
    return data
end

function Config.saveEnv(config)
    local handle = fs.open(ENV_PATH, "w")
    if not handle then
        error("Failed to write " .. ENV_PATH)
    end
    handle.writeLine("INFLUX_URL=" .. tostring(config.url))
    handle.writeLine("INFLUX_ORG=" .. tostring(config.org))
    handle.writeLine("INFLUX_BUCKET=" .. tostring(config.bucket))
    handle.writeLine("INFLUX_TOKEN=" .. tostring(config.token))
    handle.writeLine("INFLUX_NODE=" .. tostring(config.node))
    handle.close()
end

function Config.loadSettings()
    if not settings then
        return nil
    end
    local data = {
        url = settings.get(SETTINGS_PREFIX .. "url"),
        org = settings.get(SETTINGS_PREFIX .. "org"),
        bucket = settings.get(SETTINGS_PREFIX .. "bucket"),
        token = settings.get(SETTINGS_PREFIX .. "token"),
        node = settings.get(SETTINGS_PREFIX .. "node")
    }
    if not data.url and not data.token and not data.org then
        return nil
    end
    data.url = normalizeUrl(data.url or DEFAULTS.url)
    data.node = data.node or defaultNode()
    return data
end

function Config.saveSettings(config)
    if not settings then
        return
    end
    settings.set(SETTINGS_PREFIX .. "url", config.url)
    settings.set(SETTINGS_PREFIX .. "org", config.org)
    settings.set(SETTINGS_PREFIX .. "bucket", config.bucket)
    settings.set(SETTINGS_PREFIX .. "token", config.token)
    settings.set(SETTINGS_PREFIX .. "node", config.node)
    settings.save()
end

function Config.prompt()
    print("InfluxDB URL (e.g. https://influx.shelfwood.co):")
    local url = read()
    if url == "" then url = DEFAULTS.url end

    print("InfluxDB Org (default: " .. DEFAULTS.org .. "):")
    local org = read()
    if org == "" then org = DEFAULTS.org end

    print("InfluxDB Bucket (default: " .. DEFAULTS.bucket .. "):")
    local bucket = read()
    if bucket == "" then bucket = DEFAULTS.bucket end

    print("InfluxDB Token (required):")
    local token = read()

    local config = {
        url = normalizeUrl(url),
        org = org,
        bucket = bucket,
        token = token,
        node = defaultNode(),
        machine_interval_s = DEFAULTS.machine_interval_s,
        energy_interval_s = DEFAULTS.energy_interval_s,
        energy_detector_interval_s = DEFAULTS.energy_detector_interval_s,
        ae_interval_s = DEFAULTS.ae_interval_s,
        ae_slow_interval_s = DEFAULTS.ae_slow_interval_s,
        ae_slow_threshold_ms = DEFAULTS.ae_slow_threshold_ms,
        ae_top_items = DEFAULTS.ae_top_items,
        ae_top_fluids = DEFAULTS.ae_top_fluids,
        flush_interval_s = DEFAULTS.flush_interval_s,
        max_buffer_lines = DEFAULTS.max_buffer_lines
    }

    Config.saveFile(config)
    Config.saveEnv(config)
    Config.saveSettings(config)
    return config
end

function Config.ensure()
    local config = merge({}, DEFAULTS)
    local fileConfig = Config.loadFile()
    local envConfig = Config.loadEnv()
    local settingsConfig = Config.loadSettings()

    local hadFile = fileConfig ~= nil
    local hadEnv = envConfig ~= nil
    local hadSettings = settingsConfig ~= nil

    config = merge(config, fileConfig)
    config = merge(config, envConfig)
    config = merge(config, settingsConfig)

    if not config or not config.token or config.token == "" then
        config = Config.prompt()
        return config
    end

    if not config.url or config.url == "" then
        config.url = DEFAULTS.url
    end

    if not config.org or config.org == "" then
        config.org = DEFAULTS.org
    end

    if not config.bucket or config.bucket == "" then
        config.bucket = DEFAULTS.bucket
    end

    config.node = config.node or defaultNode()
    config.url = normalizeUrl(config.url)

    if not hadFile then
        Config.saveFile(config)
    end
    if not hadEnv then
        Config.saveEnv(config)
    end
    if not hadSettings then
        Config.saveSettings(config)
    end

    return config
end

return Config
