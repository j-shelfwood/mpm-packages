return function(h)
    local function getViewNames()
        local manifestPath = h.workspace .. "/views/manifest.json"
        local content = h:read_file(manifestPath)
        h:assert_not_nil(content, "views/manifest.json should exist")

        local manifest = textutils.unserialiseJSON(content)
        h:assert_not_nil(manifest, "views/manifest.json should parse")

        local views = {}
        for _, filename in ipairs(manifest.files or {}) do
            local isUtility = filename == "Manager.lua" or filename == "BaseView.lua"
            local isRenderer = filename:match("Renderers%.lua$") ~= nil
            local isSubdirectory = filename:find("/") ~= nil

            if not isUtility and not isRenderer and not isSubdirectory then
                views[#views + 1] = filename:gsub("%.lua$", "")
            end
        end

        table.sort(views)
        return views
    end

    local function getAEBoundViews()
        local views = getViewNames()
        local aeViews = {}

        for _, viewName in ipairs(views) do
            local path = h.workspace .. "/views/" .. viewName .. ".lua"
            local content = h:read_file(path) or ""
            if content:find("peripherals/AEInterface", 1, true) then
                aeViews[#aeViews + 1] = viewName
            end
        end

        table.sort(aeViews)
        return aeViews
    end

    h:test("view mounts: all mount() checks execute without throwing", function()
        h.module_cache = {}
        local views = getViewNames()

        for _, viewName in ipairs(views) do
            local View = mpm("views/" .. viewName)
            h:assert_not_nil(View, "View should load: " .. viewName)

            if type(View.mount) == "function" then
                local ok = pcall(View.mount)
                h:assert_true(ok, "mount() should not throw for view: " .. viewName)
            end
        end
    end)

    h:test("view mounts: AE views fail closed when AEInterface is unavailable", function()
        h.module_cache = {}

        local originalMpm = _G.mpm
        _G.mpm = function(name)
            if name == "peripherals/AEInterface" then
                return nil
            end
            return originalMpm(name)
        end

        local okRun, err = pcall(function()
            local views = getViewNames()
            local hadClock = false

            for _, viewName in ipairs(views) do
                local View = mpm("views/" .. viewName)
                if viewName == "Clock" then
                    hadClock = true
                end

                if View and type(View.mount) == "function" then
                    local okMount = pcall(View.mount)
                    h:assert_true(okMount, "mount() should not throw when AEInterface missing: " .. viewName)
                end
            end

            h:assert_true(hadClock, "Clock view should be present in manifest")
        end)

        _G.mpm = originalMpm
        h.module_cache = {}

        if not okRun then
            error(err)
        end
    end)

    h:test("view lifecycle: AE views init/getData do not throw when AEInterface missing", function()
        h.module_cache = {}

        local originalMpm = _G.mpm
        _G.mpm = function(name)
            if name == "peripherals/AEInterface" then
                return nil
            end
            return originalMpm(name)
        end

        local fakeMonitor = {
            getSize = function() return 16, 8 end
        }

        local okRun, err = pcall(function()
            local aeViews = getAEBoundViews()
            h:assert_true(#aeViews > 0, "Expected at least one AE-bound view")

            for _, viewName in ipairs(aeViews) do
                local View = mpm("views/" .. viewName)
                h:assert_not_nil(View, "AE view should load: " .. viewName)
                h:assert_true(type(View.new) == "function", "AE view should expose new(): " .. viewName)

                local okNew, instance = pcall(View.new, fakeMonitor, {}, "monitor_0")
                h:assert_true(okNew, "new() should not throw when AEInterface missing: " .. viewName)

                if okNew and instance and type(instance.getData) == "function" then
                    local okData = pcall(instance.getData, instance)
                    h:assert_true(okData, "getData() should not throw when AEInterface missing: " .. viewName)
                end
            end
        end)

        _G.mpm = originalMpm
        h.module_cache = {}

        if not okRun then
            error(err)
        end
    end)
end
