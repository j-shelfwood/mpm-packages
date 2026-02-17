return function(h)
    local function ensure_local_install()
        if fs.exists("/mpm/Packages/views/Manager.lua") then
            return
        end

        local realShutdown = os.shutdown
        os.shutdown = function() end
        local ok, err = pcall(function()
            dofile(h.workspace .. "/scripts/craftos_install_local.lua")
        end)
        os.shutdown = realShutdown

        h:assert_true(ok, "Local installer failed: " .. tostring(err))
    end

    h:test("installed packages: AEInterface module shape is valid", function()
        ensure_local_install()

        local Run = dofile("/mpm/Core/Commands/Run.lua")
        h:assert_not_nil(Run, "Run command should load")

        local AEInterface = mpm("peripherals/AEInterface")
        h:assert_true(type(AEInterface) == "table", "AEInterface should be a table module")
        h:assert_true(type(AEInterface.exists) == "function", "AEInterface.exists should be a function")
        h:assert_true(type(AEInterface.new) == "function", "AEInterface.new should be a function")
    end)

    h:test("installed packages: all view mount() checks do not throw", function()
        ensure_local_install()
        dofile("/mpm/Core/Commands/Run.lua")

        local ViewManager = mpm("views/Manager")
        h:assert_not_nil(ViewManager, "Installed ViewManager should load")

        local views = ViewManager.getAvailableViews()
        h:assert_true(type(views) == "table" and #views > 0, "Installed views list should be non-empty")

        for _, viewName in ipairs(views) do
            local View = ViewManager.load(viewName)
            if View and type(View.mount) == "function" then
                local ok = pcall(View.mount)
                h:assert_true(ok, "Installed mount() should not throw: " .. viewName)
            end
        end
    end)
end
