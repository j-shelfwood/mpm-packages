return function(h)
    h:test("shelfos-swarm start guard: non-pocket exits before app load", function()
        local startPath = h.workspace .. "/shelfos-swarm/start.lua"
        h:assert_true(fs.exists(startPath), "start.lua missing")

        local oldPocket = _G.pocket
        local oldPrint = _G.print
        local oldMpm = _G.mpm
        local prints = {}

        _G.pocket = nil
        _G.mpm = function()
            error("mpm should not be called when pocket API is missing")
        end
        _G.print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do
                parts[#parts + 1] = tostring(select(i, ...))
            end
            prints[#prints + 1] = table.concat(parts, " ")
        end

        local ok, err = pcall(function()
            dofile(startPath)
        end)

        _G.pocket = oldPocket
        _G.print = oldPrint
        _G.mpm = oldMpm

        h:assert_true(ok, "start.lua should return cleanly: " .. tostring(err))
        h:assert_true(#prints >= 1, "Expected explanatory output")
        h:assert_contains(table.concat(prints, "\n"), "requires a pocket computer", "Missing non-pocket guard message")
    end)

    h:test("shelfos-swarm app surface loads in CraftOS", function()
        local App = mpm("shelfos-swarm/App")
        h:assert_not_nil(App, "App module missing")
        h:assert_true(type(App.new) == "function", "App.new must exist")

        local app = App.new()
        h:assert_not_nil(app, "App.new() returned nil")
        h:assert_not_nil(app.authority, "App should initialize swarm authority")
        h:assert_true(app.channel == nil, "App channel should initialize nil")
    end)
end
