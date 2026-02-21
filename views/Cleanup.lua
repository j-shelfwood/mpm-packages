-- Cleanup.lua
-- Boot-time pruner for optional view packages.
-- Removes entire optional package directories when none of their views
-- are assigned to any monitor in the current config.

local Cleanup = {}

local PACKAGES_DIR = "/mpm/Packages/"

-- Optional packages eligible for pruning (never prune core packages)
local OPTIONAL_PACKAGES = { "views-ae2", "views-mek", "views-energy", "views-extra" }

-- Build a set of view names currently in use across all monitors
local function getUsedViews(config)
    local used = {}
    for _, monitorCfg in ipairs(config.monitors or {}) do
        if monitorCfg.view and monitorCfg.view ~= "" then
            used[monitorCfg.view] = true
        end
    end
    return used
end

-- Read the manifest for a locally installed package; returns files list or nil
local function getInstalledFiles(pkgName)
    local manifestPath = PACKAGES_DIR .. pkgName .. "/manifest.json"
    local f = fs.open(manifestPath, "r")
    if not f then return nil end
    local raw = f.readAll()
    f.close()
    local ok, manifest = pcall(textutils.unserialiseJSON, raw)
    if not ok or not manifest then return nil end
    return manifest.files or {}
end

-- Given a files list from a manifest, extract the view names (bare .lua base names,
-- no subdirectories, not utility files)
local function extractViewNames(files)
    local names = {}
    for _, filename in ipairs(files) do
        local isSubdir = filename:find("/") ~= nil
        local isUtility = filename == "Manager.lua" or filename == "BaseView.lua"
            or filename == "AEViewSupport.lua" or filename:match("Renderers%.lua$")
        if not isSubdir and not isUtility then
            local viewName = filename:gsub("%.lua$", "")
            table.insert(names, viewName)
        end
    end
    return names
end

-- Prune optional packages whose views are entirely unused.
-- @param config ShelfOS config table (with .monitors array)
-- @return number pruned package count
function Cleanup.pruneUnused(config)
    if not config then return 0 end

    local used = getUsedViews(config)
    local pruned = 0

    for _, pkgName in ipairs(OPTIONAL_PACKAGES) do
        local pkgDir = PACKAGES_DIR .. pkgName
        if fs.exists(pkgDir) then
            local files = getInstalledFiles(pkgName)
            if files then
                local views = extractViewNames(files)
                local anyUsed = false
                for _, viewName in ipairs(views) do
                    if used[viewName] then
                        anyUsed = true
                        break
                    end
                end

                if not anyUsed then
                    print("[Views] Pruning unused package: " .. pkgName)
                    fs.delete(pkgDir)
                    pruned = pruned + 1
                end
            else
                -- No readable manifest - safe to remove orphaned dir
                print("[Views] Removing unreadable package dir: " .. pkgName)
                fs.delete(pkgDir)
                pruned = pruned + 1
            end
        end
    end

    return pruned
end

return Cleanup
