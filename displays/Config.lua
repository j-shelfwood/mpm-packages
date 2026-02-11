-- Config.lua
-- Simple configuration store for displays package
-- Uses the same format as before for backwards compatibility

local Config = {}

-- Configuration file path
local CONFIG_PATH = "displays.config"

-- Load configuration from disk
-- @return config array or empty array
function Config.load()
    if not fs.exists(CONFIG_PATH) then
        return {}
    end

    local file = fs.open(CONFIG_PATH, "r")
    if not file then
        return {}
    end

    local content = file.readAll()
    file.close()

    local ok, config = pcall(textutils.unserialize, content)
    if not ok or not config then
        return {}
    end

    return config
end

-- Save configuration to disk
-- @param config Configuration array
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

-- Add a display to configuration
-- @param monitorName Peripheral name
-- @param viewName View to display
-- @param viewConfig Optional view configuration
function Config.addDisplay(config, monitorName, viewName, viewConfig)
    table.insert(config, {
        monitor = monitorName,
        view = viewName,
        config = viewConfig or {}
    })
end

-- Update a display's view
-- @param monitorName Peripheral name
-- @param viewName New view name
function Config.updateDisplayView(monitorName, viewName)
    local config = Config.load()

    for _, display in ipairs(config) do
        if display.monitor == monitorName then
            display.view = viewName
            break
        end
    end

    Config.save(config)
end

-- Get display by monitor name
function Config.getDisplay(config, monitorName)
    for _, display in ipairs(config) do
        if display.monitor == monitorName then
            return display
        end
    end
    return nil
end

-- Remove a display
function Config.removeDisplay(config, monitorName)
    for i, display in ipairs(config) do
        if display.monitor == monitorName then
            table.remove(config, i)
            return true
        end
    end
    return false
end

-- Get config path
function Config.getPath()
    return CONFIG_PATH
end

return Config
