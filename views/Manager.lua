-- Manager.lua
-- View loading and lifecycle management for ShelfOS

local Yield = mpm('utils/Yield')
local Peripherals = mpm('utils/Peripherals')

local Manager = {}

-- Cache of loaded views
local viewCache = {}
local mountErrorCache = {}
local mountableCache = nil
local mountableCacheAt = 0
local MOUNTABLE_CACHE_TTL_MS = 5000
local selectableCache = nil

local function copyArray(arr)
    local copy = {}
    for i, v in ipairs(arr or {}) do
        copy[i] = v
    end
    return copy
end

local function hasEnergyStorage()
    return Peripherals.find("energy_storage") or Peripherals.find("energyStorage")
end

local function hasEnergyDetector()
    return Peripherals.find("energy_detector")
end

-- Get list of all available views from manifest
function Manager.getAvailableViews()
    local manifestPath = "/mpm/Packages/views/manifest.json"

    if not fs.exists(manifestPath) then
        return {}
    end

    local file = fs.open(manifestPath, "r")
    if not file then
        return {}
    end

    local content = file.readAll()
    file.close()

    local ok, manifest = pcall(textutils.unserializeJSON, content)
    if not ok or not manifest then
        return {}
    end

    local views = {}
    for _, filename in ipairs(manifest.files or {}) do
        -- Skip non-view files:
        -- 1. Utility files: Manager.lua, BaseView.lua
        -- 2. Renderer helpers: *Renderers.lua (e.g., BaseViewRenderers.lua)
        -- 3. Factories: anything in subdirectories (contains '/')
        local isUtility = filename == "Manager.lua" or filename == "BaseView.lua" or filename == "AEViewSupport.lua"
        local isRenderer = filename:match("Renderers%.lua$") ~= nil
        local isSubdirectory = filename:find("/") ~= nil

        if not isUtility and not isRenderer and not isSubdirectory then
            -- Remove .lua extension
            local viewName = filename:gsub("%.lua$", "")
            table.insert(views, viewName)
        end
    end

    return views
end

-- Get selectable views for interactive UI paths (boot/config/menu).
-- This intentionally avoids mount() execution to keep first render responsive.
function Manager.getSelectableViews()
    if selectableCache then
        return copyArray(selectableCache)
    end
    selectableCache = Manager.getAvailableViews()
    return copyArray(selectableCache)
end

-- Load a view module by name
-- @param viewName View name (without .lua)
-- @return View module or nil
function Manager.load(viewName)
    -- Check cache
    if viewCache[viewName] then
        return viewCache[viewName]
    end

    -- Try to load
    local ok, View = pcall(mpm, 'views/' .. viewName)
    if not ok then
        print("[ViewManager] Error loading " .. viewName .. ": " .. tostring(View))
        return nil
    end

    -- Validate that this is actually a view module (must have new function)
    if not View or type(View) ~= "table" or type(View.new) ~= "function" then
        if View == nil then
            print("[ViewManager] Invalid view module: " .. viewName .. " (module returned nil; check /mpm/Packages install alignment)")
        else
            print("[ViewManager] Invalid view module: " .. viewName .. " (missing new function)")
        end
        return nil
    end

    viewCache[viewName] = View
    return View
end

-- Check if a view can mount (has required peripherals)
-- @param viewName View name
-- @return boolean
function Manager.canMount(viewName)
    local View = Manager.load(viewName)
    if not View then
        return false
    end

    if not View.mount then
        return true  -- No mount check = always mountable
    end

    local ok, result = pcall(View.mount)
    if not ok then
        local err = tostring(result)
        if mountErrorCache[viewName] ~= err then
            print("[ViewManager] Mount error for " .. viewName .. ": " .. err)
            mountErrorCache[viewName] = err
        end
        return false
    end
    mountErrorCache[viewName] = nil
    return result
end

-- Get list of views that can mount (with yields for responsiveness)
function Manager.getMountableViews(forceRefresh)
    local now = os.epoch("utc")
    if not forceRefresh and mountableCache and (now - mountableCacheAt) < MOUNTABLE_CACHE_TTL_MS then
        return copyArray(mountableCache)
    end

    local available = Manager.getAvailableViews()
    local mountable = {}

    for idx, viewName in ipairs(available) do
        if Manager.canMount(viewName) then
            table.insert(mountable, viewName)
        end
        -- Yield between mount checks since they may call peripheral.find()
        Yield.check(idx, 5)  -- Lower interval since each check can be slow
    end

    mountableCache = mountable
    mountableCacheAt = os.epoch("utc")

    return copyArray(mountable)
end

-- Get mountable views with stale-cache preference for UI responsiveness.
-- If stale cache exists, returns it immediately and avoids a refresh on touch paths.
function Manager.getMountableViewsFast()
    if mountableCache and #mountableCache > 0 then
        return copyArray(mountableCache)
    end
    return Manager.getMountableViews()
end

-- Get view info
-- @param viewName View name
-- @return info table or nil
function Manager.getViewInfo(viewName)
    local View = Manager.load(viewName)
    if not View then
        return nil
    end

    return {
        name = viewName,
        sleepTime = View.sleepTime or 1,
        hasConfig = View.configSchema ~= nil,
        configSchema = View.configSchema or {}
    }
end

-- Clear view cache (for reloading)
function Manager.clearCache()
    viewCache = {}
    mountErrorCache = {}
    mountableCache = nil
    mountableCacheAt = 0
    selectableCache = nil
end

function Manager.invalidateMountableCache()
    mountableCache = nil
    mountableCacheAt = 0
    selectableCache = nil
end

-- Create a view instance
-- @param viewName View name
-- @param monitor Monitor peripheral
-- @param config View configuration
-- @return instance, error
function Manager.createInstance(viewName, monitor, config)
    local View = Manager.load(viewName)
    if not View then
        return nil, "View not found: " .. viewName
    end

    local ok, instance = pcall(View.new, monitor, config or {})
    if ok then
        return instance, nil
    else
        return nil, tostring(instance)
    end
end

-- Get default config for a view
function Manager.getDefaultConfig(viewName)
    local View = Manager.load(viewName)
    if not View or not View.configSchema then
        return {}
    end

    local config = {}
    for _, field in ipairs(View.configSchema) do
        if field.default ~= nil then
            config[field.key] = field.default
        end
    end

    return config
end

-- Suggest best view based on available peripherals
-- Used for auto-discovery when no config exists
-- @return viewName, reason
function Manager.suggestView()
    -- Priority order: most specific peripheral first
    local suggestions = {
        { check = function() return Peripherals.find("me_bridge") end, view = "StorageGraph", reason = "AE2 ME Bridge detected" },
        { check = function() return Peripherals.find("rsBridge") end, view = "StorageGraph", reason = "RS Bridge detected" },
        { check = hasEnergyDetector, view = "EnergySystem", reason = "Energy detectors detected" },
        { check = function() return Peripherals.find("enrichmentChamber") end, view = "MachineGrid", reason = "Mekanism machines detected" },
        { check = hasEnergyStorage, view = "EnergyGraph", reason = "Energy storage detected" },
        { check = function() return Peripherals.find("environment_detector") end, view = "Clock", reason = "Environment detector found" },
    }

    for idx, suggestion in ipairs(suggestions) do
        local ok, result = pcall(suggestion.check)
        Yield.yield()  -- Yield after each peripheral.find()
        if ok and result then
            -- Verify view is loadable
            if Manager.canMount(suggestion.view) then
                return suggestion.view, suggestion.reason
            end
        end
    end

    -- Fallback: first mountable view, or Clock if available
    local mountable = Manager.getMountableViews()
    for _, viewName in ipairs(mountable) do
        if viewName == "Clock" then
            return "Clock", "Default fallback"
        end
    end

    if #mountable > 0 then
        return mountable[1], "First available view"
    end

    return nil, "No views available"
end

-- Get all suggested views for multiple monitors
-- Tries to assign variety when possible
-- @param monitorCount Number of monitors to assign
-- @return Array of {view, reason} suggestions
function Manager.suggestViewsForMonitors(monitorCount)
    local mountable = Manager.getMountableViews()
    local suggestions = {}

    if #mountable == 0 then
        return suggestions
    end

    -- Build prioritized list based on peripherals (with yields)
    local prioritized = {}

    -- Check for ME/RS bridge first (local or remote)
    local hasMeBridge = Peripherals.find("me_bridge")
    Yield.yield()
    local hasRsBridge = Peripherals.find("rsBridge")
    Yield.yield()

    if hasMeBridge or hasRsBridge then
        for _, v in ipairs({"NetworkDashboard", "StorageGraph", "EnergyGraph", "EnergyStatus", "CraftingQueue", "CPUOverview", "CellHealth", "ItemGauge", "ItemBrowser", "FluidGauge", "FluidBrowser", "FluidList", "ChemicalGauge", "ChemicalBrowser", "ChemicalList", "ItemChanges", "CraftingCPU", "StorageBreakdown", "CraftableBrowser", "PatternBrowser", "DriveStatus"}) do
            for _, m in ipairs(mountable) do
                if m == v then
                    table.insert(prioritized, v)
                    break
                end
            end
        end
    end

    -- Add energy if available (local or remote)
    local hasEnergy = hasEnergyStorage()
    local hasDetector = hasEnergyDetector()
    Yield.yield()

    if hasDetector then
        for _, m in ipairs(mountable) do
            if m == "EnergySystem" then
                table.insert(prioritized, m)
                break
            end
        end
    end

    if hasEnergy then
        for _, m in ipairs(mountable) do
            if m == "EnergyGraph" then
                table.insert(prioritized, m)
                break
            end
        end
    end

    -- Check for Mekanism machines (local or remote)
    local hasMekanism = Peripherals.find("enrichmentChamber") or Peripherals.find("crusher") or Peripherals.find("solarGenerator")
    Yield.yield()

    if hasMekanism then
        for _, m in ipairs(mountable) do
            if m == "MachineGrid" then
                table.insert(prioritized, m)
                break
            end
        end
    end

    -- Fill remaining with other mountable views
    for _, m in ipairs(mountable) do
        local found = false
        for _, p in ipairs(prioritized) do
            if p == m then found = true break end
        end
        if not found then
            table.insert(prioritized, m)
        end
    end

    -- Assign views to monitors
    for i = 1, monitorCount do
        local viewIndex = ((i - 1) % #prioritized) + 1
        local viewName = prioritized[viewIndex]
        table.insert(suggestions, {
            view = viewName,
            reason = i <= #prioritized and "Auto-assigned" or "Cycled"
        })
    end

    return suggestions
end

return Manager
