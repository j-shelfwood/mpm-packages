-- Installs mpm and shelfos (+ deps) from mounted /workspace into CraftOS storage.

local WORKSPACE = "/workspace"

local function ensure_dir(path)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
end

local function read_file(path)
    local f = fs.open(path, "r")
    if not f then return nil end
    local data = f.readAll()
    f.close()
    return data
end

local function write_file(path, content)
    ensure_dir(path)
    local f = fs.open(path, "w")
    if not f then return false end
    f.write(content)
    f.close()
    return true
end

local function copy_file(src, dst)
    local content = read_file(src)
    if not content then
        error("Failed to read source file: " .. src)
    end
    if not write_file(dst, content) then
        error("Failed to write destination file: " .. dst)
    end
end

local function install_mpm()
    print("[install] mpm core")
    for _, d in ipairs({
        "/mpm",
        "/mpm/Packages",
        "/mpm/Core",
        "/mpm/Core/Commands",
        "/mpm/Core/Utils",
    }) do
        if not fs.exists(d) then fs.makeDir(d) end
    end

    local manifest_content = read_file(WORKSPACE .. "/mpm/manifest.json")
    assert(manifest_content, "missing mpm/manifest.json")
    local manifest = textutils.unserializeJSON(manifest_content)
    assert(type(manifest) == "table", "invalid mpm/manifest.json")

    for _, rel in ipairs(manifest) do
        local src = WORKSPACE .. "/mpm/" .. rel
        local dst = (rel == "mpm.lua") and "/mpm.lua" or ("/mpm/" .. rel)
        copy_file(src, dst)
    end

    local taps = {
        version = 1,
        defaultTap = "official",
        taps = {
            official = {
                name = "official",
                url = "https://shelfwood-mpm-packages.netlify.app/",
                type = "direct"
            }
        }
    }
    write_file("/mpm/taps.json", textutils.serializeJSON(taps))
end

local installed = {}
local function install_package(name)
    if installed[name] then return end

    local manifest_path = string.format("%s/mpm-packages/%s/manifest.json", WORKSPACE, name)
    local manifest_content = read_file(manifest_path)
    assert(manifest_content, "missing package manifest for " .. name)
    local manifest = textutils.unserializeJSON(manifest_content)
    assert(type(manifest) == "table", "invalid package manifest for " .. name)

    if type(manifest.dependencies) == "table" then
        for _, dep in ipairs(manifest.dependencies) do
            install_package(dep)
        end
    end

    print("[install] package " .. name)
    local base = "/mpm/Packages/" .. name
    if not fs.exists(base) then fs.makeDir(base) end

    write_file(base .. "/manifest.json", textutils.serializeJSON(manifest))

    for _, rel in ipairs(manifest.files or {}) do
        copy_file(string.format("%s/mpm-packages/%s/%s", WORKSPACE, name, rel), base .. "/" .. rel)
    end

    installed[name] = true
end

local function verify()
    local required = {
        "/mpm.lua",
        "/mpm/bootstrap.lua",
        "/mpm/taps.json",
        "/mpm/Packages/shelfos/start.lua",
        "/mpm/Packages/net/Pairing.lua",
        "/mpm/Packages/ui/Controller.lua",
        "/mpm/Packages/views/Manager.lua",
    }

    for _, path in ipairs(required) do
        assert(fs.exists(path), "missing: " .. path)
    end

    local pkgs = fs.list("/mpm/Packages")
    table.sort(pkgs)
    print("[verify] installed packages: " .. table.concat(pkgs, ", "))
end

install_mpm()
install_package("shelfos")
verify()
print("[ok] local install complete")
os.shutdown()
