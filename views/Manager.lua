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
local viewSources = {}

-- Core packages always installed
local CORE_PACKAGES = { "views" }

-- Optional packages: stub table mapping package name -> { views, category, label }
-- This allows the Select View screen to show all views even before packages are installed.
local OPTIONAL_PACKAGES = {
    {
        name     = "views-ae2",
        label    = "AE2 Storage",
        category = "ae2",
        views    = {
            "StorageGraph", "StorageBreakdown", "CellHealth", "DriveStatus",
            "ItemBrowser", "ItemList", "ItemGauge", "ItemChanges",
            "FluidBrowser", "FluidList", "FluidGauge", "FluidChanges",
            "ChemicalBrowser", "ChemicalList", "ChemicalGauge", "ChemicalChanges",
            "CraftingQueue", "CraftingCPU", "CPUOverview",
            "CraftableBrowser", "PatternBrowser",
            "EnergyGraph", "EnergyStatus",
        },
    },
    {
        name     = "views-mek",
        label    = "Mekanism",
        category = "mek",
        views    = {
            "MekDashboard", "MachineGrid", "MachineList",
            "MekMachineGauge", "MekGeneratorStatus", "MekMultiblockStatus",
        },
    },
    {
        name     = "views-energy",
        label    = "Energy",
        category = "energy",
        views    = {
            "EnergyOverview", "EnergySystem", "EnergyFlowGraph",
        },
    },
}

-- Human-friendly labels for individual views
local VIEW_LABELS = {
    -- AE2
    StorageGraph     = "Storage Graph",
    StorageBreakdown = "Storage Breakdown",
    CellHealth       = "Cell Health",
    DriveStatus      = "Drive Status",
    ItemBrowser      = "Item Browser",
    ItemList         = "Item List",
    ItemGauge        = "Item Gauge",
    ItemChanges      = "Item Changes",
    FluidBrowser     = "Fluid Browser",
    FluidList        = "Fluid List",
    FluidGauge       = "Fluid Gauge",
    FluidChanges     = "Fluid Changes",
    ChemicalBrowser  = "Chemical Browser",
    ChemicalList     = "Chemical List",
    ChemicalGauge    = "Chemical Gauge",
    ChemicalChanges  = "Chemical Changes",
    CraftingQueue    = "Crafting Queue",
    CraftingCPU      = "Crafting CPU",
    CPUOverview      = "CPU Overview",
    CraftableBrowser = "Craftable Browser",
    PatternBrowser   = "Pattern Browser",
    EnergyGraph      = "Energy Graph [AE2]",
    EnergyStatus     = "Energy Status [AE2]",
    -- Mekanism
    MekDashboard       = "Mek Dashboard",
    MachineGrid        = "Machine Grid",
    MachineList        = "Machine List",
    MekMachineGauge    = "Machine Gauge",
    MekGeneratorStatus = "Generator Status",
    MekMultiblockStatus = "Multiblock Status",
    -- Energy
    EnergyOverview  = "Energy Overview",
    EnergySystem    = "Energy System",
    EnergyFlowGraph = "Energy Flow Graph",
    -- Core
    NetworkDashboard = "Network Dashboard",
    Clock            = "Clock",
}

-- Category metadata for grouping in the UI
local CATEGORIES = {
    { id = "core",   label = "General" },
    { id = "ae2",    label = "AE2 Storage" },
    { id = "mek",    label = "Mekanism" },
    { id = "energy", label = "Energy" },
}

-- Which category does a core-package view belong to?
local CORE_VIEW_CATEGORY = {
    Clock            = "core",
    NetworkDashboard = "core",
}

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
    local detector = Peripherals.find("energy_detector")
    if detector then return detector end
    for _, name in ipairs(Peripherals.getNames()) do
        local p = Peripherals.wrap(name)
        if p and type(p.getTransferRate) == "function" and type(p.getTransferRateLimit) == "function" then
            return p
        end
    end
    return nil
end

-- Check whether an optional package is installed on disk
local function isPackageInstalled(pkgName)
    return fs.exists("/mpm/Packages/" .. pkgName)
end

-- Get list of all available views from installed core package manifests
local function getCoreViews()
    local views = {}
    for _, packageName in ipairs(CORE_PACKAGES) do
        local manifestPath = "/mpm/Packages/" .. packageName .. "/manifest.json"
        if fs.exists(manifestPath) then
            local file = fs.open(manifestPath, "r")
            if file then
                local content = file.readAll()
                file.close()
                local ok, manifest = pcall(textutils.unserializeJSON, content)
                if ok and manifest then
                    for _, filename in ipairs(manifest.files or {}) do
                        local isUtility = filename == "Manager.lua" or filename == "BaseView.lua"
                            or filename == "AEViewSupport.lua" or filename == "Cleanup.lua"
                            or filename == "PackageInstaller.lua"
                        local isRenderer = filename:match("Renderers%.lua$") ~= nil
                        local isSubdirectory = filename:find("/") ~= nil
                        if not isUtility and not isRenderer and not isSubdirectory then
                            local viewName = filename:gsub("%.lua$", "")
                            if not viewSources[viewName] then
                                viewSources[viewName] = packageName
                                table.insert(views, {
                                    name      = viewName,
                                    package   = packageName,
                                    installed = true,
                                    category  = CORE_VIEW_CATEGORY[viewName] or "core",
                                })
                            end
                        end
                    end
                end
            end
        end
    end
    return views
end

-- Build the full flat view list: core views + all optional views (installed or not)
function Manager.getAvailableViews()
    viewSources = {}
    local views = getCoreViews()

    for _, pkg in ipairs(OPTIONAL_PACKAGES) do
        local installed = isPackageInstalled(pkg.name)
        for _, viewName in ipairs(pkg.views) do
            if not viewSources[viewName] then
                viewSources[viewName] = pkg.name
                table.insert(views, {
                    name      = viewName,
                    package   = pkg.name,
                    installed = installed,
                    category  = pkg.category,
                })
            end
        end
    end

    return views
end

-- Returns grouped structure for the Select View UI.
-- Each group: { label, category, views = { {name, package, installed, label} } }
function Manager.getAvailableViewsGrouped()
    local all = Manager.getAvailableViews()

    -- Build category buckets
    local buckets = {}
    local bucketOrder = {}
    for _, cat in ipairs(CATEGORIES) do
        buckets[cat.id] = { label = cat.label, category = cat.id, views = {} }
        table.insert(bucketOrder, cat.id)
    end

    for _, view in ipairs(all) do
        local cat = view.category or "core"
        if not buckets[cat] then
            buckets[cat] = { label = cat, category = cat, views = {} }
            table.insert(bucketOrder, cat)
        end
        table.insert(buckets[cat].views, {
            name      = view.name,
            package   = view.package,
            installed = view.installed,
            label     = VIEW_LABELS[view.name] or view.name,
        })
    end

    local groups = {}
    for _, catId in ipairs(bucketOrder) do
        local bucket = buckets[catId]
        if bucket and #bucket.views > 0 then
            table.insert(groups, bucket)
        end
    end

    return groups
end

-- Flat selectable list (name strings) - used by legacy paths
function Manager.getSelectableViews()
    if selectableCache then
        return copyArray(selectableCache)
    end
    local all = Manager.getAvailableViews()
    selectableCache = {}
    for _, v in ipairs(all) do
        table.insert(selectableCache, v.name)
    end
    return copyArray(selectableCache)
end

-- Get the package name that owns a view
function Manager.getViewPackage(viewName)
    if not viewSources[viewName] then
        Manager.getAvailableViews()
    end
    return viewSources[viewName]
end

-- Check if a view's package is installed
function Manager.isViewInstalled(viewName)
    local pkg = Manager.getViewPackage(viewName)
    if not pkg then return false end
    if pkg == "views" then return true end
    return isPackageInstalled(pkg)
end

-- Load a view module by name
-- @param viewName View name (without .lua)
-- @return View module or nil
function Manager.load(viewName)
    if viewCache[viewName] then
        return viewCache[viewName]
    end

    if not viewSources[viewName] then
        Manager.getAvailableViews()
    end

    local packageName = viewSources[viewName]
    if not packageName then return nil end

    -- Don't attempt load if package not installed
    if packageName ~= "views" and not isPackageInstalled(packageName) then
        return nil
    end

    local ok, View = pcall(mpm, packageName .. '/' .. viewName)
    if not ok then
        print("[ViewManager] Error loading " .. viewName .. ": " .. tostring(View))
        return nil
    end

    if not View or type(View) ~= "table" or type(View.new) ~= "function" then
        if View == nil then
            print("[ViewManager] Invalid view module: " .. viewName .. " (module returned nil)")
        else
            print("[ViewManager] Invalid view module: " .. viewName .. " (missing new function)")
        end
        return nil
    end

    viewCache[viewName] = View
    return View
end

-- Check if a view can mount (has required peripherals)
function Manager.canMount(viewName)
    local View = Manager.load(viewName)
    if not View then return false end

    if not View.mount then return true end

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

-- Get list of views that can mount (installed + peripheral check)
function Manager.getMountableViews(forceRefresh)
    local now = os.epoch("utc")
    if not forceRefresh and mountableCache and (now - mountableCacheAt) < MOUNTABLE_CACHE_TTL_MS then
        return copyArray(mountableCache)
    end

    local available = Manager.getAvailableViews()
    local mountable = {}

    for idx, view in ipairs(available) do
        if view.installed and Manager.canMount(view.name) then
            table.insert(mountable, view.name)
        end
        Yield.check(idx, 5)
    end

    mountableCache = mountable
    mountableCacheAt = os.epoch("utc")

    return copyArray(mountable)
end

function Manager.getMountableViewsFast()
    if mountableCache and #mountableCache > 0 then
        return copyArray(mountableCache)
    end
    return Manager.getMountableViews()
end

-- Get view info
function Manager.getViewInfo(viewName)
    local View = Manager.load(viewName)
    if not View then return nil end

    return {
        name       = viewName,
        sleepTime  = View.sleepTime or 1,
        hasConfig  = View.configSchema ~= nil,
        configSchema = View.configSchema or {}
    }
end

-- Get human-friendly label for a view
function Manager.getViewLabel(viewName)
    return VIEW_LABELS[viewName] or viewName
end

-- Clear view cache (for reloading)
function Manager.clearCache()
    viewCache = {}
    mountErrorCache = {}
    mountableCache = nil
    mountableCacheAt = 0
    selectableCache = nil
    viewSources = {}
    local ok, AEViewSupport = pcall(mpm, 'views/AEViewSupport')
    if ok and AEViewSupport and type(AEViewSupport.invalidateCapabilities) == "function" then
        AEViewSupport.invalidateCapabilities()
    end
end

function Manager.invalidateMountableCache()
    mountableCache = nil
    mountableCacheAt = 0
    selectableCache = nil
    viewSources = {}
    local ok, AEViewSupport = pcall(mpm, 'views/AEViewSupport')
    if ok and AEViewSupport and type(AEViewSupport.invalidateCapabilities) == "function" then
        AEViewSupport.invalidateCapabilities()
    end
end

-- Create a view instance
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
    if not View or not View.configSchema then return {} end

    local config = {}
    for _, field in ipairs(View.configSchema) do
        if field.default ~= nil then
            config[field.key] = field.default
        end
    end
    return config
end

-- Suggest best view based on available peripherals
function Manager.suggestView()
    local suggestions = {
        { check = function() return Peripherals.find("me_bridge") end,         view = "StorageGraph",     reason = "AE2 ME Bridge detected" },
        { check = function() return Peripherals.find("rsBridge") end,          view = "StorageGraph",     reason = "RS Bridge detected" },
        { check = hasEnergyDetector,                                            view = "EnergySystem",     reason = "Energy detectors detected" },
        { check = function() return Peripherals.find("enrichmentChamber") end,  view = "MachineGrid",      reason = "Mekanism machines detected" },
        { check = hasEnergyStorage,                                             view = "EnergyGraph",      reason = "Energy storage detected" },
        { check = function() return Peripherals.find("environment_detector") end, view = "Clock",          reason = "Environment detector found" },
    }

    for idx, suggestion in ipairs(suggestions) do
        local ok, result = pcall(suggestion.check)
        Yield.yield()
        if ok and result then
            if Manager.canMount(suggestion.view) then
                return suggestion.view, suggestion.reason
            end
        end
    end

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

-- Suggest views for multiple monitors
function Manager.suggestViewsForMonitors(monitorCount)
    local mountable = Manager.getMountableViews()
    local suggestions = {}

    if #mountable == 0 then return suggestions end

    local prioritized = {}

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

    local hasDetector = hasEnergyDetector()
    Yield.yield()
    local hasEnergy = hasEnergyStorage()

    if hasDetector then
        for _, m in ipairs(mountable) do
            if m == "EnergySystem" then table.insert(prioritized, m) break end
        end
    end

    if hasEnergy then
        for _, m in ipairs(mountable) do
            if m == "EnergyGraph" then table.insert(prioritized, m) break end
        end
    end

    local hasMekanism = Peripherals.find("enrichmentChamber") or Peripherals.find("crusher") or Peripherals.find("solarGenerator")
    Yield.yield()

    if hasMekanism then
        for _, m in ipairs(mountable) do
            if m == "MachineGrid" then table.insert(prioritized, m) break end
        end
    end

    for _, m in ipairs(mountable) do
        local found = false
        for _, p in ipairs(prioritized) do
            if p == m then found = true break end
        end
        if not found then table.insert(prioritized, m) end
    end

    for i = 1, monitorCount do
        local viewIndex = ((i - 1) % #prioritized) + 1
        local viewName = prioritized[viewIndex]
        table.insert(suggestions, {
            view   = viewName,
            reason = i <= #prioritized and "Auto-assigned" or "Cycled"
        })
    end

    return suggestions
end

return Manager
