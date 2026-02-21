return function(h)
    h:test("baseview touch contract: custom views expose handleTouch when onTouch is defined", function()
        local BaseView = mpm("views/BaseView")

        local touched = 0
        local View = BaseView.custom({
            getData = function()
                return { ok = true }
            end,
            render = function()
            end,
            onTouch = function(self, x, y)
                touched = touched + 1
                return x == 2 and y == 3
            end
        })

        local fakeMonitor = {
            getSize = function() return 10, 6 end,
            setBackgroundColor = function() end,
            setTextColor = function() end,
            setCursorPos = function() end,
            write = function() end,
        }

        local instance = View.new(fakeMonitor, {}, "monitor_0")

        h:assert_true(type(View.handleTouch) == "function", "Expected handleTouch for custom view onTouch")
        h:assert_true(View.handleTouch(instance, 2, 3), "Expected touch handler return value to propagate")
        h:assert_false(View.handleTouch(instance, 1, 1), "Expected false when onTouch returns false")
        h:assert_eq(2, touched, "Expected onTouch to be invoked for each call")
    end)
end
