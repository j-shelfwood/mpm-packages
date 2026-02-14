-- Config.lua
-- Persistent configuration store for ShelfOS
--
-- Split module:
--   ConfigMigration.lua - Legacy displays.config migration

local Paths = mpm('shelfos/core/Paths')
local ConfigMigration = mpm('shelfos/core/ConfigMigration')

local Config = {}

-- Configuration file path (use centralized Paths module)
local CONFIG_PATH = Paths.CONFIG

-- Default configuration
local DEFAULT_CONFIG = {
    version = 1,
    computer = {
        id = nil,  -- Set during setup
        name = "Unnamed Computer"
    },
    monitors = {},
    network = {
        secret = nil,  -- Set during setup if networking enabled
        enabled = false
    },
    settings = {
        defaultSleepTime = 1,
        touchFeedback = true,
        showViewIndicator = true,
        theme = "default"  -- Options: default, dark, highContrast, solarized, monokai
    }
}

-- Deep copy a table
local function deepCopy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for k, v in pairs(orig) do
            copy[k] = deepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

-- Merge tables (b overwrites a)
local function merge(a, b)
    local result = deepCopy(a)
    for k, v in pairs(b) do
        if type(v) == 'table' and type(result[k]) == 'table' then
            result[k] = merge(result[k], v)
        else
            result[k] = deepCopy(v)
        end
    end
    return result
end

-- Migration delegated to ConfigMigration module

-- Load configuration from disk
-- @return config table or nil
function Config.load()
    -- Try migration from displays.config first
    local migrated = ConfigMigration.migrateFromDisplays(DEFAULT_CONFIG)
    if migrated then
        -- Note: Do NOT auto-generate network secret
        -- Computer must be paired with pocket to join swarm
        Config.save(migrated)
        -- Delete old config
        fs.delete("displays.config")
        print("[ShelfOS] Migrated from displays.config")
        return migrated
    end

    if not fs.exists(CONFIG_PATH) then
        return nil
    end

    local file = fs.open(CONFIG_PATH, "r")
    if not file then
        return nil
    end

    local content = file.readAll()
    file.close()

    local ok, config = pcall(textutils.unserialize, content)
    if not ok or not config then
        return nil
    end

    -- Migrate zone → computer key if needed
    if config.zone and not config.computer then
        config.computer = config.zone
        config.zone = nil
    end

    -- Merge with defaults to ensure all fields exist
    config = merge(DEFAULT_CONFIG, config)

    -- Note: Do NOT auto-generate network secret here
    -- Computer must be paired with pocket to join swarm

    return config
end

-- Save configuration to disk
-- @param config Configuration table
-- @return success
function Config.save(config)
    local file = fs.open(CONFIG_PATH, "w")
    if not file then
        return false
    end

    file.write(textutils.serialize(config))
    file.close()
    return true
end

-- Check if configuration exists
function Config.exists()
    return fs.exists(CONFIG_PATH)
end

-- Create a new configuration with defaults
-- @param computerId Computer identifier
-- @param computerName Computer name
-- @return new config
function Config.create(computerId, computerName)
    local config = deepCopy(DEFAULT_CONFIG)
    config.computer.id = computerId or ("computer_" .. os.getComputerID())
    config.computer.name = computerName or ("Computer " .. os.getComputerID())
    return config
end

-- Add a monitor to configuration
-- @param config Configuration table
-- @param peripheralName Peripheral name
-- @param viewName View to display
-- @param viewConfig View-specific configuration
function Config.addMonitor(config, peripheralName, viewName, viewConfig)
    table.insert(config.monitors, {
        peripheral = peripheralName,
        label = peripheralName,  -- Can be customized
        view = viewName,
        viewConfig = viewConfig or {}
    })
end

-- Remove a monitor from configuration
function Config.removeMonitor(config, peripheralName)
    for i, m in ipairs(config.monitors) do
        if m.peripheral == peripheralName then
            table.remove(config.monitors, i)
            return true
        end
    end
    return false
end

-- Get monitor configuration
function Config.getMonitor(config, peripheralName)
    for _, m in ipairs(config.monitors) do
        if m.peripheral == peripheralName then
            return m
        end
    end
    return nil
end

-- Update monitor view
function Config.setMonitorView(config, peripheralName, viewName, viewConfig)
    local monitor = Config.getMonitor(config, peripheralName)
    if monitor then
        monitor.view = viewName
        if viewConfig then
            monitor.viewConfig = viewConfig
        end
        return true
    end
    return false
end

-- Update monitor view config
function Config.updateMonitorConfig(config, peripheralName, key, value)
    local monitor = Config.getMonitor(config, peripheralName)
    if monitor then
        monitor.viewConfig = monitor.viewConfig or {}
        monitor.viewConfig[key] = value
        return true
    end
    return false
end

-- Set network secret
function Config.setNetworkSecret(config, secret)
    config.network = config.network or {}
    config.network.secret = secret
    config.network.enabled = secret ~= nil
end

-- Check if computer is paired with a swarm
-- @param config Configuration table
-- @return true if has valid secret
function Config.isInSwarm(config)
    return config and config.network and config.network.secret ~= nil
end

-- Get default config
function Config.getDefaults()
    return deepCopy(DEFAULT_CONFIG)
end

-- Validate configuration
function Config.validate(config)
    if not config then
        return false, "Config is nil"
    end

    if not config.computer or not config.computer.id then
        return false, "Missing computer ID"
    end

    if not config.monitors then
        return false, "Missing monitors array"
    end

    return true, nil
end

-- Get config file path
function Config.getPath()
    return CONFIG_PATH
end

-- Auto-create configuration by discovering monitors and assigning views
-- Used for zero-touch first boot
-- @return config, monitorsFound
function Config.autoCreate()
    local ViewManager = mpm('views/Manager')

    -- Generate computer identity
    local computerId = "computer_" .. os.getComputerID() .. "_" .. (os.epoch("utc") % 100000)
    local computerName = os.getComputerLabel() or ("Computer " .. os.getComputerID())

    local config = deepCopy(DEFAULT_CONFIG)
    config.computer.id = computerId
    config.computer.name = computerName

    -- Note: Do NOT auto-generate network secret
    -- Computer starts unpaired - must pair with pocket to join swarm
    -- network.secret = nil, network.enabled = false (from DEFAULT_CONFIG)

    -- Discover monitors
    local monitors = {}
    local peripherals = peripheral.getNames()

    for _, name in ipairs(peripherals) do
        if peripheral.hasType(name, "monitor") then
            table.insert(monitors, name)
        end
    end

    if #monitors == 0 then
        return config, 0
    end

    -- Get view suggestions
    local suggestions = ViewManager.suggestViewsForMonitors(#monitors)

    -- Assign views to monitors
    for i, monitorName in ipairs(monitors) do
        local suggestion = suggestions[i] or { view = "WeatherClock", reason = "Default" }
        table.insert(config.monitors, {
            peripheral = monitorName,
            label = monitorName,
            view = suggestion.view,
            viewConfig = ViewManager.getDefaultConfig(suggestion.view)
        })
    end

    return config, #monitors
end

return Config
