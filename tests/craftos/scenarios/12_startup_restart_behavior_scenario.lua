return function(h)
    local function run_mpm(...)
        local args = { ... }
        local entry = assert(loadfile("/mpm.lua"))
        return pcall(function()
            entry(table.unpack(args))
        end)
    end

    local function ensure_local_install()
        if fs.exists("/mpm.lua") then
            return
        end

        local realShutdown = os.shutdown
        os.shutdown = function() end
        local ok, err = pcall(function()
            dofile(h.workspace .. "/scripts/craftos_install_local.lua")
        end)
        os.shutdown = realShutdown

        h:assert_true(ok, "Local install prerequisite failed: " .. tostring(err))
    end

    h:test("startup behavior: generated startup.lua executes full boot sequence despite command failures", function()
        ensure_local_install()

        local ok, err = run_mpm("startup", "influx-collector")
        h:assert_true(ok, "mpm startup influx-collector failed: " .. tostring(err))

        local startupContent, readErr = h:read_file("/startup.lua")
        h:assert_not_nil(startupContent, "Failed to read startup.lua: " .. tostring(readErr))
        h:assert_contains(startupContent, "shell.run('mpm selfupdate')", "startup.lua missing selfupdate command")
        h:assert_contains(startupContent, "shell.run('mpm update')", "startup.lua missing update command")
        h:assert_contains(startupContent, "shell.run('mpm run influx-collector')", "startup.lua missing configured run command")

        local configContent, configErr = h:read_file("/startup.config")
        h:assert_not_nil(configContent, "Failed to read startup.config: " .. tostring(configErr))
        local config = textutils.unserialiseJSON(configContent)
        h:assert_not_nil(config, "startup.config should contain valid JSON")
        h:assert_eq("influx-collector", config.package, "startup.config package mismatch")
        h:assert_eq("", config.parameters, "startup.config parameters mismatch")

        local script = assert(loadfile("/startup.lua"))
        local oldShell = _G.shell
        local calls = {}

        _G.shell = {
            run = function(cmd)
                calls[#calls + 1] = cmd
                if cmd == "mpm selfupdate" then
                    return false
                end
                return true
            end
        }

        local execOk, execErr = pcall(script)
        _G.shell = oldShell

        h:assert_true(execOk, "Generated startup.lua should execute cleanly: " .. tostring(execErr))
        h:assert_eq(3, #calls, "startup.lua should attempt all three startup commands")
        h:assert_eq("mpm selfupdate", calls[1], "Unexpected first startup command")
        h:assert_eq("mpm update", calls[2], "Unexpected second startup command")
        h:assert_eq("mpm run influx-collector", calls[3], "Unexpected third startup command")
    end)

    h:test("startup behavior: refresh regenerates corrupted startup.lua", function()
        ensure_local_install()

        local write = fs.open("/startup.lua", "w")
        h:assert_not_nil(write, "Failed to open /startup.lua for corruption test")
        write.write("-- corrupted startup")
        write.close()

        local ok, err = run_mpm("startup", "--refresh")
        h:assert_true(ok, "mpm startup --refresh failed: " .. tostring(err))

        local refreshed, readErr = h:read_file("/startup.lua")
        h:assert_not_nil(refreshed, "Failed to read refreshed startup.lua: " .. tostring(readErr))
        h:assert_contains(refreshed, "mpm selfupdate", "Refreshed startup.lua should include selfupdate")
        h:assert_contains(refreshed, "mpm update", "Refreshed startup.lua should include update")
        h:assert_contains(refreshed, "mpm run influx-collector", "Refreshed startup.lua should include configured run target")
    end)
end
