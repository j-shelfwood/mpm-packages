return function(h)
    h:test("view rendering: Clock renders expected structure on screen buffer", function()
        h:with_ui_driver(51, 19, function(driver)
            local Clock = mpm("views/Clock")
            local instance = Clock.new(driver.buffer, {
                timeFormat = "24h",
                showBiome = true
            }, "test_terminal")

            local data = Clock.getData(instance)
            Clock.renderWithData(instance, data)

            h:assert_screen_contains(driver, "CLOCK", "Clock title should render")
            h:assert_screen_contains(driver, "Weather:", "Clock weather section missing")
            h:assert_screen_contains(driver, "CC time (no detector)", "Clock fallback status missing")
        end)
    end)
end
