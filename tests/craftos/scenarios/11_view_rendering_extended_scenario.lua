return function(h)
    h:test("view rendering: EnergyStatus detailed mode renders critical sections", function()
        h:with_ui_driver(51, 19, function(driver)
            local EnergyStatus = mpm("views/EnergyStatus")
            local instance = EnergyStatus.new(driver.buffer, {
                displayMode = "detailed",
                warningThreshold = 100
            }, "test_terminal")

            EnergyStatus.renderWithData(instance, {
                stored = 5000,
                capacity = 10000,
                percentage = 50,
                input = 350,
                usage = 200,
                netFlow = 150,
                avgFlow = 150,
                timeToFull = 600,
                timeToEmpty = nil,
                history = {}
            })

            h:assert_screen_contains(driver, "ENERGY STATUS", "Detailed header should render")
            h:assert_screen_contains(driver, "Stored:", "Storage section should render")
            h:assert_screen_contains(driver, "NET", "Net flow section should render")
        end)
    end)

    h:test("view rendering: NetworkDashboard compact mode renders summary metrics", function()
        h:with_ui_driver(51, 19, function(driver)
            local NetworkDashboard = mpm("views/NetworkDashboard")
            local instance = NetworkDashboard.new(driver.buffer, {
                displayMode = "compact"
            }, "test_terminal")

            NetworkDashboard.renderWithData(instance, {
                isConnected = true,
                isOnline = true,
                energyStored = 7500,
                energyCapacity = 10000,
                energyUsage = 80,
                energyInput = 120,
                itemsUsed = 450,
                itemsTotal = 1000,
                fluidsUsed = 100,
                fluidsTotal = 1000,
                cpuTotal = 4,
                cpuBusy = 1,
                activeCrafts = 2
            })

            h:assert_screen_contains(driver, "ME *", "Compact title/status should render")
            h:assert_screen_contains(driver, "Stor", "Storage summary line should render")
            h:assert_screen_contains(driver, "CPU", "CPU summary line should render")
        end)
    end)

    h:test("view rendering: DriveStatus grid renders cell count and percent", function()
        h:with_ui_driver(51, 19, function(driver)
            local DriveStatus = mpm("views/DriveStatus")
            local instance = DriveStatus.new(driver.buffer, {
                showEmpty = true
            }, "test_terminal")

            DriveStatus.renderWithData(instance, {
                {
                    cells = { { bytesTotal = 1024 } },
                    usedBytes = 512,
                    totalBytes = 1024
                }
            })

            h:assert_screen_contains(driver, "ME Drives", "DriveStatus header should render")
            h:assert_screen_contains(driver, "1 cell", "Drive cell count should render")
            h:assert_screen_contains(driver, "50%", "Drive usage percent should render")
        end)
    end)

    h:test("view rendering: CraftingCPU busy mode shows task and progress", function()
        h:with_ui_driver(51, 19, function(driver)
            local CraftingCPU = mpm("views/CraftingCPU")
            local instance = CraftingCPU.new(driver.buffer, {
                cpu = "CPU-1"
            }, "test_terminal")

            CraftingCPU.renderWithData(instance, {
                cpu = {
                    name = "CPU-1",
                    isBusy = true,
                    storage = 4096,
                    coProcessors = 2
                },
                currentTask = {
                    completion = 0.5,
                    resource = {
                        displayName = "Refined Storage Cable",
                        count = 64
                    },
                    quantity = 64
                }
            })

            h:assert_screen_contains(driver, "CRAFTING", "Busy status should render")
            h:assert_screen_contains(driver, "Refined Storage Cable", "Task name should render")
            h:assert_screen_contains(driver, "x64", "Task quantity should render")
        end)
    end)
end
