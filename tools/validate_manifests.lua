-- validate_manifests.lua
-- Validates that all manifest.json files include all .lua files in their directories
-- Run this before deploying to catch missing files early

local function getPackageDirs()
    -- List of package directories to check
    return {
        "views",
        "utils",
        "peripherals",
        "ui",
        "net",
        "shelfos",
        "tools"
    }
end

local function readManifest(packageDir)
    local path = "/mpm/Packages/" .. packageDir .. "/manifest.json"
    if not fs.exists(path) then
        return nil, "Manifest not found: " .. path
    end

    local file = fs.open(path, "r")
    if not file then
        return nil, "Could not open: " .. path
    end

    local content = file.readAll()
    file.close()

    local ok, manifest = pcall(textutils.unserializeJSON, content)
    if not ok or not manifest then
        return nil, "Invalid JSON in: " .. path
    end

    return manifest
end

local function getLuaFiles(packageDir)
    local basePath = "/mpm/Packages/" .. packageDir
    local files = {}

    local function scanDir(dir, prefix)
        if not fs.exists(dir) then return end

        for _, name in ipairs(fs.list(dir)) do
            local fullPath = dir .. "/" .. name
            local relativePath = prefix and (prefix .. "/" .. name) or name

            if fs.isDir(fullPath) then
                -- Recurse into subdirectories
                scanDir(fullPath, relativePath)
            elseif name:match("%.lua$") then
                table.insert(files, relativePath)
            end
        end
    end

    scanDir(basePath, nil)
    return files
end

local function validatePackage(packageDir)
    local manifest, err = readManifest(packageDir)
    if not manifest then
        return false, { err }
    end

    local manifestFiles = {}
    for _, file in ipairs(manifest.files or {}) do
        manifestFiles[file] = true
    end

    local diskFiles = getLuaFiles(packageDir)
    local diskFilesSet = {}
    for _, file in ipairs(diskFiles) do
        diskFilesSet[file] = true
    end

    local issues = {}

    -- Check for files on disk not in manifest
    for _, file in ipairs(diskFiles) do
        if not manifestFiles[file] then
            table.insert(issues, "Missing from manifest: " .. file)
        end
    end

    -- Check for files in manifest not on disk
    for file in pairs(manifestFiles) do
        if not diskFilesSet[file] then
            table.insert(issues, "In manifest but not on disk: " .. file)
        end
    end

    return #issues == 0, issues
end

local function main()
    print("Manifest Validation Tool")
    print("========================")
    print("")

    local allValid = true
    local packages = getPackageDirs()

    for _, packageDir in ipairs(packages) do
        local valid, issues = validatePackage(packageDir)

        if valid then
            print("[OK] " .. packageDir)
        else
            allValid = false
            print("[FAIL] " .. packageDir)
            for _, issue in ipairs(issues) do
                print("  - " .. issue)
            end
        end
    end

    print("")
    if allValid then
        print("All manifests are valid!")
    else
        print("Some manifests have issues. Fix them before deploying.")
    end

    return allValid
end

-- Run if executed directly
if not ... then
    main()
end

return {
    validate = validatePackage,
    validateAll = main
}
