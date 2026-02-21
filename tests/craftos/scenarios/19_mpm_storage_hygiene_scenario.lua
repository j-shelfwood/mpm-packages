return function(h)
    local WORKSPACE = "/workspace"

    local function read_file(path)
        local f = fs.open(path, "r")
        if not f then
            return nil
        end
        local data = f.readAll()
        f.close()
        return data
    end

    local function write_file(path, content)
        local dir = fs.getDir(path)
        if dir ~= "" and not fs.exists(dir) then
            fs.makeDir(dir)
        end
        local f = fs.open(path, "w")
        if not f then
            return false
        end
        f.write(content)
        f.close()
        return true
    end

    local function write_json(path, tbl)
        return write_file(path, textutils.serializeJSON(tbl))
    end

    local function wipe(path)
        if fs.exists(path) then
            fs.delete(path)
        end
    end

    local function provision_mpm()
        wipe("/startup.lua")
        wipe("/startup.config")
        wipe("/mpm.lua")
        wipe("/mpm")

        local realShutdown = os.shutdown
        os.shutdown = function() end
        local ok, err = pcall(function()
            dofile(WORKSPACE .. "/mpm-packages/scripts/craftos_install_local.lua")
        end)
        os.shutdown = realShutdown

        h:assert_true(ok, "Local installer failed: " .. tostring(err))
        h:assert_true(fs.exists("/mpm.lua"), "Missing /mpm.lua after provisioning")
    end

    local function make_response(body)
        return {
            readAll = function()
                return body
            end,
            close = function()
            end,
            getResponseCode = function()
                return 200
            end
        }
    end

    local function run_mpm_with_http_and_capture(args, routes)
        local lines = {}
        local entry = assert(loadfile("/mpm.lua"))
        local httpApi = http or {}
        if not http then
            _G.http = httpApi
        end

        local ok = h:with_overrides(_G, {
            print = function(...)
                local parts = {}
                for i = 1, select("#", ...) do
                    parts[#parts + 1] = tostring(select(i, ...))
                end
                lines[#lines + 1] = table.concat(parts, " ")
            end
        }, function()
            return h:with_overrides(http, {
                get = function(url)
                    local body = routes[url]
                    if body == nil then
                        return nil
                    end
                    return make_response(body)
                end
            }, function()
                return pcall(function()
                    entry(table.unpack(args))
                end)
            end)
        end)
        return ok, lines
    end

    h:test("update: removes stale package files, prunes orphan deps, reports disk usage", function()
        provision_mpm()

        write_json("/mpm/taps.json", {
            version = 1,
            defaultTap = "local",
            taps = {
                ["local"] = {
                    name = "local",
                    url = "https://packages.local/",
                    type = "direct"
                }
            }
        })

        write_json("/mpm/Packages/demo/manifest.json", {
            name = "demo",
            description = "demo package",
            files = {"a.lua", "old.lua"},
            dependencies = {"dep1"},
            _tap = "local",
            _tapUrl = "https://packages.local/",
            _installReason = "manual"
        })
        write_file("/mpm/Packages/demo/a.lua", "return 'old-a'")
        write_file("/mpm/Packages/demo/old.lua", "return 'stale'")

        write_json("/mpm/Packages/orphan/manifest.json", {
            name = "orphan",
            files = {"orphan.lua"},
            _installReason = "dependency"
        })
        write_file("/mpm/Packages/orphan/orphan.lua", "return true")

        local routes = {
            ["https://packages.local/demo/manifest.json"] = textutils.serializeJSON({
                name = "demo",
                description = "demo package",
                files = {"a.lua", "new.lua"},
                dependencies = {"dep1"}
            }),
            ["https://packages.local/demo/a.lua"] = "return 'new-a'",
            ["https://packages.local/demo/new.lua"] = "return 'new-file'",
            ["https://packages.local/dep1/manifest.json"] = textutils.serializeJSON({
                name = "dep1",
                files = {"dep.lua"}
            }),
            ["https://packages.local/dep1/dep.lua"] = "return 'dep'"
        }

        local ok, lines = run_mpm_with_http_and_capture({"update", "demo"}, routes)
        h:assert_true(ok, "mpm update demo failed")

        h:assert_false(fs.exists("/mpm/Packages/demo/old.lua"), "Stale file old.lua should be removed")
        h:assert_true(fs.exists("/mpm/Packages/demo/new.lua"), "New file new.lua should exist")
        h:assert_true(fs.exists("/mpm/Packages/dep1/dep.lua"), "Dependency dep1 should be installed")
        h:assert_false(fs.exists("/mpm/Packages/orphan"), "Orphan dependency package should be pruned")

        local output = table.concat(lines, "\n")
        h:assert_contains(output, "Dependency cleanup:", "Update summary should include dependency cleanup")
        h:assert_contains(output, "Disk usage:", "Update should print disk usage")
    end)

    h:test("selfupdate: prunes stale core files and reports disk usage", function()
        provision_mpm()

        write_file("/mpm/Core/Utils/LegacyLeak.lua", "return {}")
        write_json("/mpm/manifest.json", {
            "mpm.lua",
            "bootstrap.lua",
            "Core/Utils/LegacyLeak.lua"
        })

        local routes = {
            ["https://shelfwood-mpm.netlify.app/manifest.json"] = textutils.serializeJSON({
                "mpm.lua",
                "bootstrap.lua"
            }),
            ["https://shelfwood-mpm.netlify.app/mpm.lua"] = "local bootstrap = dofile('/mpm/bootstrap.lua') local tArgs = {...} bootstrap.handleCommand(tArgs)",
            ["https://shelfwood-mpm.netlify.app/bootstrap.lua"] = read_file("/mpm/bootstrap.lua")
        }

        local ok, lines = run_mpm_with_http_and_capture({"selfupdate"}, routes)
        h:assert_true(ok, "mpm selfupdate failed")
        h:assert_false(fs.exists("/mpm/Core/Utils/LegacyLeak.lua"), "Stale core file should be removed during selfupdate")

        local output = table.concat(lines, "\n")
        h:assert_contains(output, "Disk usage:", "Selfupdate should print disk usage")
    end)

    h:test("prune: dry-run does not delete orphaned dependency packages", function()
        provision_mpm()

        write_json("/mpm/Packages/app/manifest.json", {
            name = "app",
            files = {"start.lua"},
            dependencies = {"dep1"},
            _installReason = "manual"
        })
        write_file("/mpm/Packages/app/start.lua", "return true")

        write_json("/mpm/Packages/dep1/manifest.json", {
            name = "dep1",
            files = {"dep.lua"},
            _installReason = "dependency"
        })
        write_file("/mpm/Packages/dep1/dep.lua", "return true")

        write_json("/mpm/Packages/orphan/manifest.json", {
            name = "orphan",
            files = {"x.lua"},
            _installReason = "dependency"
        })
        write_file("/mpm/Packages/orphan/x.lua", "return true")

        local ok = pcall(function()
            local entry = assert(loadfile("/mpm.lua"))
            entry("prune", "--dry-run")
        end)
        h:assert_true(ok, "mpm prune --dry-run should succeed")
        h:assert_true(fs.exists("/mpm/Packages/orphan"), "Dry-run should not remove orphan package")
    end)
end
