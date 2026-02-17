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
end
