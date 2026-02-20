return function(h)
    h:test("event loop: drainMonitorTouches drops only targeted touches", function()
        local EventLoop = mpm("ui/EventLoop")

        os.queueEvent("monitor_touch", "left", 1, 1)
        os.queueEvent("monitor_touch", "right", 2, 2)
        os.queueEvent("eventloop_test_custom", "ok")

        local drained = EventLoop.drainMonitorTouches("left", 10)
        h:assert_eq(1, drained, "Expected exactly one drained left-monitor touch")

        os.queueEvent("eventloop_test_marker")

        local sawRightTouch = false
        local sawCustom = false
        local sawLeftTouch = false

        while true do
            local event, p1 = os.pullEventRaw()
            if event == "eventloop_test_marker" then
                break
            elseif event == "monitor_touch" and p1 == "right" then
                sawRightTouch = true
            elseif event == "monitor_touch" and p1 == "left" then
                sawLeftTouch = true
            elseif event == "eventloop_test_custom" then
                sawCustom = true
            end
        end

        h:assert_true(sawRightTouch, "Expected right-monitor touch to remain queued")
        h:assert_true(sawCustom, "Expected non-touch events to remain queued")
        h:assert_false(sawLeftTouch, "Expected left-monitor touch to be drained")
    end)

    h:test("event loop: touch guard suppresses guarded monitor touches", function()
        local EventLoop = mpm("ui/EventLoop")

        EventLoop.armTouchGuard("left", 1000)

        os.queueEvent("monitor_touch", "left", 3, 3)
        os.queueEvent("monitor_touch", "right", 4, 4)

        local kind, x, y, side = EventLoop.waitForMonitorEvent(nil, {
            acceptAnyWhenNil = true
        })

        h:assert_eq("touch", kind, "Expected monitor touch event")
        h:assert_eq("right", side, "Expected guarded left touch to be skipped")
        h:assert_eq(4, x, "Unexpected x coordinate")
        h:assert_eq(4, y, "Unexpected y coordinate")

        EventLoop.armTouchGuard("left", 0)
    end)
end
