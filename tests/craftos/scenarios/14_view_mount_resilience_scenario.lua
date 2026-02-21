return function(h)
    local function collectViewEntries()
        local entries = {}

        for _, packageName in ipairs({ "views", "views-ae2", "views-mek", "views-energy" }) do
            local manifestPath = h.workspace .. "/" .. packageName .. "/manifest.json"
            local content = h:read_file(manifestPath)
            if content then
                local manifest = textutils.unserialiseJSON(content)
                if manifest then
                    for _, filename in ipairs(manifest.files or {}) do
                        local isUtility = filename == "Manager.lua" or filename == "BaseView.lua"
                        local isRenderer = filename:match("Renderers%.lua$") ~= nil
                        local isSubdirectory = filename:find("/") ~= nil

                        if not isUtility and not isRenderer and not isSubdirectory then
                            entries[#entries + 1] = {
                                package = packageName,
                                name = filename:gsub("%.lua$", ""),
                                file = filename
                            }
                        end
                    end
                end
            end
        end

        table.sort(entries, function(a, b)
            return a.name < b.name
        end)

        return entries
    end

    local function getViewNames()
        local entries = collectViewEntries()
        local views = {}
        for _, entry in ipairs(entries) do
            views[#views + 1] = entry.name
        end
        return views
    end

    local function getAEBoundViews()
        local entries = collectViewEntries()
        local aeViews = {}

        for _, entry in ipairs(entries) do
            local path = h.workspace .. "/" .. entry.package .. "/" .. entry.file
            local content = h:read_file(path) or ""
            if content:find("peripherals/AEInterface", 1, true) then
                aeViews[#aeViews + 1] = { package = entry.package, name = entry.name }
            end
        end

        table.sort(aeViews, function(a, b)
            return a.name < b.name
        end)
        return aeViews
    end

    h:test("view mounts: all mount() checks execute without throwing", function()
        h.module_cache = {}
        local entries = collectViewEntries()

        for _, entry in ipairs(entries) do
            local View = mpm(entry.package .. "/" .. entry.name)
            h:assert_not_nil(View, "View should load: " .. entry.name)

            if type(View.mount) == "function" then
                local ok = pcall(View.mount)
                h:assert_true(ok, "mount() should not throw for view: " .. entry.name)
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
            local entries = collectViewEntries()
            local hadClock = false

            for _, entry in ipairs(entries) do
                local View = mpm(entry.package .. "/" .. entry.name)
                if entry.name == "Clock" then
                    hadClock = true
                end

                if View and type(View.mount) == "function" then
                    local okMount = pcall(View.mount)
                    h:assert_true(okMount, "mount() should not throw when AEInterface missing: " .. entry.name)
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

            for _, entry in ipairs(aeViews) do
                local View = mpm(entry.package .. "/" .. entry.name)
                h:assert_not_nil(View, "AE view should load: " .. entry.name)
                h:assert_true(type(View.new) == "function", "AE view should expose new(): " .. entry.name)

                local okNew, instance = pcall(View.new, fakeMonitor, {}, "monitor_0")
                h:assert_true(okNew, "new() should not throw when AEInterface missing: " .. entry.name)

                if okNew and instance and type(instance.getData) == "function" then
                    local okData = pcall(instance.getData, instance)
                    h:assert_true(okData, "getData() should not throw when AEInterface missing: " .. entry.name)
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
