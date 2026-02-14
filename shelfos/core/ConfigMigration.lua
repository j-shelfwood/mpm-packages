-- ConfigMigration.lua
-- Migration utilities for ShelfOS configuration
-- Handles legacy displays.config to shelfos.config migration
-- Extracted from Config.lua for maintainability

local ConfigMigration = {}

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

-- Migrate from legacy displays.config to shelfos.config
-- @param DEFAULT_CONFIG The default configuration template
-- @return migrated config or nil if no migration needed
function ConfigMigration.migrateFromDisplays(DEFAULT_CONFIG)
    if not fs.exists("displays.config") then
        return nil
    end

    local file = fs.open("displays.config", "r")
    if not file then
        return nil
    end

    local content = file.readAll()
    file.close()

    local ok, oldConfig = pcall(textutils.unserialize, content)
    if not ok or not oldConfig then
        return nil
    end

    -- Handle both formats: {displays={...}, settings={...}} or just [{monitor=..., view=...}]
    local displays = oldConfig.displays or oldConfig

    -- Generate zone identity
    local zoneId = "zone_" .. os.getComputerID() .. "_" .. (os.epoch("utc") % 100000)
    local zoneName = os.getComputerLabel() or ("Zone " .. os.getComputerID())

    local newConfig = deepCopy(DEFAULT_CONFIG)
    newConfig.zone.id = zoneId
    newConfig.zone.name = zoneName

    -- Migrate monitors
    if type(displays) == "table" then
        for _, display in ipairs(displays) do
            if display.monitor and display.view then
                table.insert(newConfig.monitors, {
                    peripheral = display.monitor,
                    label = display.monitor,
                    view = display.view,
                    viewConfig = display.config or {}
                })
            end
        end
    end

    -- Migrate theme if present
    if oldConfig.settings and oldConfig.settings.theme then
        newConfig.settings.theme = oldConfig.settings.theme
    end

    return newConfig
end

return ConfigMigration
