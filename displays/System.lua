-- This module is the core system responsible for running the different displays and their configured views.
local this

this = {
    manageDisplay = function(display)
        local ViewClass = mpm('views/' .. display.view)
        local monitor = peripheral.wrap(display.monitor)
        local viewInstance = ViewClass.new(monitor, display.config)

        while true do
            local status, err = pcall(function()
                ViewClass.render(viewInstance)
            end)
            if not status then
                print("Error rendering view: " .. err)
            end
            if ViewClass.sleepTime then
                sleep(ViewClass.sleepTime)
            end
        end
    end,

    listenForCancel = function()
        while true do
            local event, key = os.pullEvent("key")
            if key == keys.q then
                print("Cancellation key pressed. Exiting...")
                os.exit()
            end
        end
    end,

    run = function()
        local config = mpm('displays/Config').load()

        local tasks = {}
        for _, display in ipairs(config) do
            table.insert(tasks, function()
                this.manageDisplay(display)
            end)
        end

        table.insert(tasks, this.listenForCancel)

        parallel.waitForAll(table.unpack(tasks))
    end
}

return this
