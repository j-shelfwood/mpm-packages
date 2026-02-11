-- Manager.lua
-- View loading and lifecycle management for ShelfOS

local Manager = {}

-- Cache of loaded views
local viewCache = {}

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
        -- Skip Manager.lua itself
        if filename ~= "Manager.lua" then
            -- Remove .lua extension
            local viewName = filename:gsub("%.lua$", "")
            table.insert(views, viewName)
        end
    end

    return views
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
    if ok and View then
        viewCache[viewName] = View
        return View
    end

    return nil
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

    local ok, canMount = pcall(View.mount)
    return ok and canMount
end

-- Get list of views that can mount
function Manager.getMountableViews()
    local available = Manager.getAvailableViews()
    local mountable = {}

    for _, viewName in ipairs(available) do
        if Manager.canMount(viewName) then
            table.insert(mountable, viewName)
        end
    end

    return mountable
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
        { check = function() return peripheral.find("me_bridge") end, view = "StorageGraph", reason = "AE2 ME Bridge detected" },
        { check = function() return peripheral.find("rsBridge") end, view = "StorageGraph", reason = "RS Bridge detected" },
        { check = function() return peripheral.find("energyStorage") end, view = "EnergyGraph", reason = "Energy storage detected" },
        { check = function() return peripheral.find("environment_detector") end, view = "Clock", reason = "Environment detector found" },
    }

    for _, suggestion in ipairs(suggestions) do
        local ok, result = pcall(suggestion.check)
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

    -- Build prioritized list based on peripherals
    local prioritized = {}

    -- Check for ME/RS bridge first
    if peripheral.find("me_bridge") or peripheral.find("rsBridge") then
        for _, v in ipairs({"StorageGraph", "EnergyGraph", "ItemCounter", "FluidGauge", "ItemChanges", "LowStock", "CraftingCPU"}) do
            for _, m in ipairs(mountable) do
                if m == v then
                    table.insert(prioritized, v)
                    break
                end
            end
        end
    end

    -- Add energy if available
    if peripheral.find("energyStorage") then
        for _, m in ipairs(mountable) do
            if m == "EnergyGraph" then
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
