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

-- Rename a configured monitor peripheral entry.
-- Preserves custom labels; only rewrites label when it still matches the old name.
-- If the target name already exists, drops the old duplicate entry.
-- @param config Configuration table
-- @param oldPeripheral Existing configured peripheral name
-- @param newPeripheral New peripheral name
-- @return boolean changed
function Config.renameMonitor(config, oldPeripheral, newPeripheral)
    if not config or not config.monitors or not oldPeripheral or not newPeripheral then
        return false
    end

    if oldPeripheral == newPeripheral then
        return Config.getMonitor(config, oldPeripheral) ~= nil
    end

    local oldIndex = nil
    local newIndex = nil

    for i, entry in ipairs(config.monitors) do
        if entry.peripheral == oldPeripheral then
            oldIndex = i
        end
        if entry.peripheral == newPeripheral then
            newIndex = i
        end
    end

    if not oldIndex then
        return false
    end

    if newIndex and newIndex ~= oldIndex then
        table.remove(config.monitors, oldIndex)
        return true
    end

    local entry = config.monitors[oldIndex]
    entry.peripheral = newPeripheral
    if entry.label == oldPeripheral then
        entry.label = newPeripheral
    end

    return true
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

-- CC:Tweaked side names for directly-attached peripherals
local SIDES = { "top", "bottom", "left", "right", "front", "back" }

local function isSideName(name)
    for _, side in ipairs(SIDES) do
        if name == side then return true end
    end
    return false
end

-- Discover monitors, deduplicating when the same physical monitor
-- appears under both a side name (direct attachment) and a network name
-- (via wired modem). Prefers side names as canonical local identifiers when
-- both names refer to the same physical monitor.
-- Note: monitor_touch/monitor_resize may report either side or network ID.
-- @return monitors (deduplicated list), aliases (table: skipped_name → canonical_name)
function Config.discoverMonitors()
    local allNames = peripheral.getNames()
    local monitorNames = {}

    for _, name in ipairs(allNames) do
        if peripheral.hasType(name, "monitor") then
            table.insert(monitorNames, name)
        end
    end

    -- Separate side-attached monitors from network monitors
    local sideMonitors = {}
    local networkMonitors = {}

    for _, name in ipairs(monitorNames) do
        if isSideName(name) then
            table.insert(sideMonitors, name)
        else
            table.insert(networkMonitors, name)
        end
    end

    local aliases = {}  -- skipped network name → canonical side name

    -- No side monitors = no possible duplicates
    if #sideMonitors == 0 then
        return monitorNames, aliases
    end

    -- Detect duplicates: set cursor position via side name, read via network name.
    -- If they match for two distinct marker positions, they're the same physical device.
    local skip = {}

    for _, sideName in ipairs(sideMonitors) do
        local sideP = peripheral.wrap(sideName)
        if sideP then
            -- Save original cursor position
            local origX, origY = sideP.getCursorPos()

            -- Set unique marker position
            sideP.setCursorPos(43, 29)

            for _, netName in ipairs(networkMonitors) do
                if not skip[netName] then
                    local netP = peripheral.wrap(netName)
                    if netP then
                        local cx, cy = netP.getCursorPos()
                        if cx == 43 and cy == 29 then
                            -- Confirm with second marker to avoid false positives
                            sideP.setCursorPos(17, 11)
                            cx, cy = netP.getCursorPos()
                            if cx == 17 and cy == 11 then
                                skip[netName] = true
                                aliases[netName] = sideName
                            end
                        end
                    end
                end
            end

            -- Restore cursor position
            sideP.setCursorPos(origX, origY)
        end
    end

    -- Build deduplicated list (side names preferred)
    local result = {}
    for _, name in ipairs(monitorNames) do
        if not skip[name] then
            table.insert(result, name)
        end
    end

    return result, aliases
end

-- Known view renames: old name -> new name
-- When views are renamed/replaced, add mappings here so existing configs auto-migrate
local VIEW_RENAMES = {
    MachineActivity = "MachineGrid",
    MachineStatus   = "MachineGrid",
    EnergyFlow      = "EnergyFlowGraph",
    -- Gauge/list/browser views consolidated into ResourceBrowser
    ItemGauge       = "ResourceBrowser",
    FluidGauge      = "ResourceBrowser",
    ChemicalGauge   = "ResourceBrowser",
    ItemList        = "ResourceBrowser",
    FluidList       = "ResourceBrowser",
    ChemicalList    = "ResourceBrowser",
    ItemBrowser     = "ResourceBrowser",
    FluidBrowser    = "ResourceBrowser",
    ChemicalBrowser = "ResourceBrowser",
    -- Changes views consolidated into ResourceChanges
    ItemChanges     = "ResourceChanges",
    FluidChanges    = "ResourceChanges",
    ChemicalChanges = "ResourceChanges",
    -- EnergyGraph folded into EnergyStatus graph mode
    EnergyGraph     = "EnergyStatus",
}

local function applyResourceType(entry, resourceType)
    entry.viewConfig = entry.viewConfig or {}
    entry.viewConfig.resourceType = resourceType
end

local VIEW_CONFIG_MIGRATIONS = {
    ItemGauge = function(entry) applyResourceType(entry, "item") end,
    FluidGauge = function(entry) applyResourceType(entry, "fluid") end,
    ChemicalGauge = function(entry) applyResourceType(entry, "chemical") end,
    ItemList = function(entry) applyResourceType(entry, "item") end,
    FluidList = function(entry) applyResourceType(entry, "fluid") end,
    ChemicalList = function(entry) applyResourceType(entry, "chemical") end,
    ItemBrowser = function(entry) applyResourceType(entry, "item") end,
    FluidBrowser = function(entry) applyResourceType(entry, "fluid") end,
    ChemicalBrowser = function(entry) applyResourceType(entry, "chemical") end,
    ItemChanges = function(entry) applyResourceType(entry, "item") end,
    FluidChanges = function(entry) applyResourceType(entry, "fluid") end,
    ChemicalChanges = function(entry) applyResourceType(entry, "chemical") end,
    EnergyGraph = function(entry)
        entry.viewConfig = entry.viewConfig or {}
        entry.viewConfig.displayMode = "graph"
    end
}

-- Reconcile existing config against actual hardware and view availability.
-- Fixes duplicate entries, remaps aliased names, adds new monitors,
-- and auto-migrates renamed/deleted views.
-- Called on every boot after Config.load() to self-heal config issues.
-- @param config Existing configuration table
-- @return changed (boolean), summary (string)
function Config.reconcile(config)
    local ViewManager = mpm('views/Manager')
    local monitors, aliases = Config.discoverMonitors()
    local changed = false
    local actions = {}

    -- Build set of canonical monitor names
    local canonicalSet = {}
    for _, name in ipairs(monitors) do
        canonicalSet[name] = true
    end

    -- Phase 1: Remap aliased entries (network name → side name)
    -- e.g., config has "monitor_5" but canonical name is "right"
    for _, entry in ipairs(config.monitors) do
        local canonical = aliases[entry.peripheral]
        if canonical then
            table.insert(actions, "Remapped " .. entry.peripheral .. " -> " .. canonical)
            entry.peripheral = canonical
            entry.label = canonical
            changed = true
        end
    end

    -- Phase 2: Deduplicate config entries pointing to same peripheral
    -- After remapping, two entries might now have the same peripheral name
    local seen = {}
    local deduped = {}
    for _, entry in ipairs(config.monitors) do
        if not seen[entry.peripheral] then
            seen[entry.peripheral] = true
            table.insert(deduped, entry)
        else
            table.insert(actions, "Removed duplicate entry for " .. entry.peripheral)
            changed = true
        end
    end
    config.monitors = deduped

    -- Phase 2b: Optional pruning of missing monitors.
    -- Leave disabled by default to avoid nuking configs when peripherals are offline.
    if config.settings and config.settings.pruneMissingMonitors == true and #monitors > 0 then
        local pruned = {}
        for _, entry in ipairs(config.monitors) do
            if canonicalSet[entry.peripheral] then
                table.insert(pruned, entry)
            else
                table.insert(actions, "Removed missing monitor " .. tostring(entry.peripheral))
                changed = true
            end
        end
        config.monitors = pruned
    end

    -- Phase 3: Validate and auto-migrate view names
    -- Handles renamed/deleted views so monitors don't show errors
    -- getAvailableViews() returns {name, package, installed, category} tables
    local availableViews = ViewManager.getAvailableViews()
    local availableSet = {}
    for _, entry in ipairs(availableViews) do
        local viewName = type(entry) == "table" and entry.name or entry
        if viewName then availableSet[viewName] = true end
    end

    for _, entry in ipairs(config.monitors) do
        if entry.view and not availableSet[entry.view] then
            local originalView = entry.view
            -- Check known renames first
            local renamed = VIEW_RENAMES[originalView]
            if renamed and availableSet[renamed] then
                table.insert(actions, "Migrated view " .. originalView .. " -> " .. renamed .. " on " .. entry.peripheral)
                entry.view = renamed
                entry.viewConfig = ViewManager.getDefaultConfig(renamed)
                local migrate = VIEW_CONFIG_MIGRATIONS[originalView]
                if migrate then
                    migrate(entry)
                end
                changed = true
            else
                -- View is gone with no known replacement - suggest best alternative
                local suggestion, reason = ViewManager.suggestView()
                local fallback = suggestion or "Clock"
                table.insert(actions, "Replaced missing view " .. entry.view .. " -> " .. fallback .. " on " .. entry.peripheral)
                entry.view = fallback
                entry.viewConfig = ViewManager.getDefaultConfig(fallback)
                changed = true
            end
        end
    end

    -- Phase 4: Add newly-discovered monitors not in config
    local configuredSet = {}
    for _, entry in ipairs(config.monitors) do
        configuredSet[entry.peripheral] = true
    end

    local newMonitors = {}
    for _, name in ipairs(monitors) do
        if not configuredSet[name] then
            table.insert(newMonitors, name)
        end
    end

    if #newMonitors > 0 then
        local suggestions = ViewManager.suggestViewsForMonitors(#newMonitors)
        for i, monitorName in ipairs(newMonitors) do
            local suggestion = suggestions[i] or { view = "Clock", reason = "Default" }
            table.insert(config.monitors, {
                peripheral = monitorName,
                label = monitorName,
                view = suggestion.view,
                viewConfig = ViewManager.getDefaultConfig(suggestion.view)
            })
            table.insert(actions, "Added new monitor " .. monitorName .. " -> " .. suggestion.view)
            changed = true
        end
    end

    -- Build summary string
    local summary = #actions > 0 and table.concat(actions, ", ") or nil

    return changed, summary
end

-- Auto-create configuration by discovering monitors and assigning views
-- Used for zero-touch first boot
-- @return config, monitorsFound
function Config.autoCreate()
    local ViewManager = mpm('views/Manager')
    local resetMode = Paths.consumeResetMarker()
    local forceClock = resetMode == "clock"

    -- Generate computer identity
    local computerId = "computer_" .. os.getComputerID() .. "_" .. (os.epoch("utc") % 100000)
    local computerName = os.getComputerLabel() or ("Computer " .. os.getComputerID())

    local config = deepCopy(DEFAULT_CONFIG)
    config.computer.id = computerId
    config.computer.name = computerName

    -- Note: Do NOT auto-generate network secret
    -- Computer starts unpaired - must pair with pocket to join swarm
    -- network.secret = nil, network.enabled = false (from DEFAULT_CONFIG)

    -- Discover monitors (with deduplication)
    local monitors = Config.discoverMonitors()

    if #monitors == 0 then
        if forceClock then
            Paths.writeResetMarker("clock")
        end
        return config, 0
    end

    local suggestions = {}
    if not forceClock then
        -- Get view suggestions
        suggestions = ViewManager.suggestViewsForMonitors(#monitors)
    end

    -- Assign views to monitors
    for i, monitorName in ipairs(monitors) do
        local suggestion
        if forceClock then
            suggestion = { view = "Clock", reason = "Reset default" }
        else
            suggestion = suggestions[i] or { view = "Clock", reason = "Default" }
        end
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
