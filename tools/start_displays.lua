local config = textutils.unserialize(fs.open("displays.config", "r").readAll())

-- Function to manage display updates
local function manageDisplay(display)
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
        -- Use the sleep time specified in the view module, default to 1 second if not specified
        if ViewClass.sleepTime then
            sleep(ViewClass.sleepTime)
        end
    end
end

-- Create tasks for each display
local tasks = {}
for _, display in ipairs(config) do
    table.insert(tasks, function()
        manageDisplay(display)
    end)
end

-- Run all tasks in parallel
parallel.waitForAll(table.unpack(tasks))
local config = textutils.unserialize(fs.open("displays.config", "r").readAll())

-- Function to manage display updates
local function manageDisplay(display)
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
        -- Use the sleep time specified in the view module, default to 1 second if not specified
        if ViewClass.sleepTime then
            sleep(ViewClass.sleepTime)
        end
    end
end

-- Function to listen for key press to cancel the script
local function listenForCancel()
    while true do
        local event, key = os.pullEvent("key")
        if key == keys.q then
            print("Cancellation key pressed. Exiting...")
            os.exit()
        end
    end
end

-- Create tasks for each display
local tasks = {}
for _, display in ipairs(config) do
    table.insert(tasks, function()
        manageDisplay(display)
    end)
end

-- Add the key listener task
table.insert(tasks, listenForCancel)

-- Run all tasks in parallel
parallel.waitForAll(table.unpack(tasks))
