-- PackageInstaller.lua
-- Inline package installer for ShelfOS runtime.
-- Does NOT use exports() - uses raw CC:Tweaked APIs only.
-- Allows MonitorConfigMenu to install view packages on-demand.

local PackageInstaller = {}

local PACKAGES_DIR = "/mpm/Packages/"
local TAP_URL = "https://shelfwood-mpm-packages.netlify.app/"

-- Read taps.json to get the configured default tap URL
local function getTapUrl()
    local f = fs.open("/mpm/taps.json", "r")
    if not f then return TAP_URL end
    local raw = f.readAll()
    f.close()
    local ok, data = pcall(textutils.unserialiseJSON, raw)
    if not ok or not data then return TAP_URL end
    local defaultName = data.defaultTap or "official"
    local tap = data.taps and data.taps[defaultName]
    if tap and tap.url then return tap.url end
    return TAP_URL
end

-- HTTP GET helper, returns content string or nil, err
local function httpGet(url)
    local ok, response = pcall(http.get, url)
    if not ok or not response then
        return nil, "HTTP request failed: " .. tostring(response)
    end
    local content = response.readAll()
    response.close()
    if not content then
        return nil, "Empty response from: " .. url
    end
    return content, nil
end

-- Write content to path, creating dirs as needed
local function writeFile(path, content)
    local dir = fs.getDir(path)
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local f = fs.open(path, "w")
    if not f then return false end
    f.write(content)
    f.close()
    return true
end

-- Check if a package is installed locally
function PackageInstaller.isInstalled(pkgName)
    return fs.exists(PACKAGES_DIR .. pkgName)
end

-- Install a single package (no recursive dependency handling - deps must exist)
-- Returns true, nil on success; false, errMsg on failure
-- onProgress(msg) optional callback for status lines
local function installOne(pkgName, tapUrl, onProgress)
    local log = onProgress or function() end

    local manifestUrl = tapUrl .. pkgName .. "/manifest.json"
    log("Fetching manifest...")
    local manifestContent, err = httpGet(manifestUrl)
    if not manifestContent then
        return false, "Cannot reach package '" .. pkgName .. "': " .. (err or "unknown")
    end

    local ok, manifest = pcall(textutils.unserialiseJSON, manifestContent)
    if not ok or not manifest then
        return false, "Invalid manifest for '" .. pkgName .. "'"
    end

    local pkgDir = PACKAGES_DIR .. pkgName
    if not fs.exists(pkgDir) then
        fs.makeDir(pkgDir)
    end

    -- Write manifest
    manifest._installReason = "manual"
    local manifestPath = pkgDir .. "/manifest.json"
    if not writeFile(manifestPath, textutils.serializeJSON(manifest)) then
        return false, "Failed to write manifest"
    end

    -- Download each file
    local files = manifest.files or {}
    for i, filename in ipairs(files) do
        log("["..i.."/"..#files.."] " .. filename)
        local fileUrl = tapUrl .. pkgName .. "/" .. filename
        local content, ferr = httpGet(fileUrl)
        if not content then
            fs.delete(pkgDir)
            return false, "Failed to download " .. filename .. ": " .. (ferr or "")
        end
        local filePath = pkgDir .. "/" .. filename
        if not writeFile(filePath, content) then
            fs.delete(pkgDir)
            return false, "Failed to write " .. filename
        end
    end

    return true, nil
end

-- Install a package and its missing dependencies.
-- @param pkgName string Package name (e.g. "views-ae2")
-- @param onProgress function|nil Called with status strings during install
-- @return boolean success, string|nil errorMsg
function PackageInstaller.install(pkgName, onProgress)
    local log = onProgress or function() end
    local tapUrl = getTapUrl()

    -- Fetch remote manifest to discover dependencies
    local manifestUrl = tapUrl .. pkgName .. "/manifest.json"
    local manifestContent, err = httpGet(manifestUrl)
    if not manifestContent then
        return false, "Cannot reach '" .. pkgName .. "': " .. (err or "unknown")
    end

    local ok, manifest = pcall(textutils.unserialiseJSON, manifestContent)
    if not ok or not manifest then
        return false, "Invalid manifest for '" .. pkgName .. "'"
    end

    -- Install dependencies first (shallow - assumes core deps are always present)
    for _, dep in ipairs(manifest.dependencies or {}) do
        if not PackageInstaller.isInstalled(dep) then
            log("Installing dependency: " .. dep)
            local depOk, depErr = installOne(dep, tapUrl, log)
            if not depOk then
                return false, "Dependency '" .. dep .. "' failed: " .. (depErr or "")
            end
        end
    end

    -- Install the package itself
    log("Installing " .. pkgName .. "...")
    local success, installErr = installOne(pkgName, tapUrl, log)
    if not success then
        return false, installErr
    end

    return true, nil
end

-- Disk space check: returns free bytes at "/"
function PackageInstaller.getFreeBytes()
    return fs.getFreeSpace("/")
end

return PackageInstaller
