return function(h)
    local function run_mpm(...)
        local args = { ... }
        local entry = assert(loadfile("/mpm.lua"))
        return pcall(function()
            entry(table.unpack(args))
        end)
    end

    local function wipe(path)
        if fs.exists(path) then
            fs.delete(path)
        end
    end

    local function reset_install_state()
        wipe("/startup.lua")
        wipe("/startup.config")
        wipe("/mpm.lua")
        wipe("/mpm")
    end

    h:test("provisioning: local mpm+influx-collector install is reproducible", function()
        reset_install_state()

        local realShutdown = os.shutdown
        os.shutdown = function() end
        local ok, err = pcall(function()
            dofile(h.workspace .. "/scripts/craftos_install_local.lua")
        end)
        os.shutdown = realShutdown

        h:assert_true(ok, "Local installer failed: " .. tostring(err))
        h:assert_true(fs.exists("/mpm.lua"), "Missing /mpm.lua")
        h:assert_true(fs.exists("/mpm/Packages/influx-collector/start.lua"), "Missing installed influx-collector package")
        h:assert_true(fs.exists("/mpm/Packages/utils/Theme.lua"), "Missing transitive dependency package")
    end)

    h:test("startup: mpm startup influx-collector writes boot scripts", function()
        local ok, err = run_mpm("startup", "influx-collector")
        h:assert_true(ok, "mpm startup influx-collector failed: " .. tostring(err))

        h:assert_true(fs.exists("/startup.config"), "Missing /startup.config")
        h:assert_true(fs.exists("/startup.lua"), "Missing /startup.lua")

        local content, err = h:read_file("/startup.lua")
        h:assert_not_nil(content, "Failed to read startup.lua: " .. tostring(err))
        h:assert_contains(content, "mpm selfupdate", "startup.lua missing selfupdate step")
        h:assert_contains(content, "mpm update", "startup.lua missing package update step")
        h:assert_contains(content, "mpm run influx-collector", "startup.lua missing influx-collector run step")

        local helpOk = run_mpm("help")
        h:assert_true(helpOk, "mpm help should execute from /mpm.lua entrypoint")
    end)
end
