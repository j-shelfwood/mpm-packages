-- Manager.lua
-- View lifecycle management and loading

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
        -- Remove .lua extension
        local viewName = filename:gsub("%.lua$", "")
        table.insert(views, viewName)
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

return Manager
