-- System.lua
-- Display management system - rewritten to follow shelfos patterns
-- Uses timer-based rendering and proper touch zone handling

local Config = mpm('displays/Config')
local TouchZones = mpm('ui/TouchZones')
local ViewManager = mpm('views/Manager')

local System = {}

-- Display class (similar to shelfos/core/Monitor)
local Display = {}
Display.__index = Display

function Display.new(config, availableViews)
    local self = setmetatable({}, Display)

    self.peripheralName = config.monitor
    self.peripheral = peripheral.wrap(self.peripheralName)
    self.connected = self.peripheral ~= nil

    if not self.connected then
        return nil
    end

    self.availableViews = availableViews
    self.currentIndex = 1
    self.viewName = config.view
    self.viewConfig = config.config or {}

    self.view = nil
    self.viewInstance = nil
    self.touchZones = nil
    self.renderTimer = nil
    self.indicatorTimer = nil
    self.showingIndicator = false

    -- Find initial view index
    for i, name in ipairs(availableViews) do
        if name == self.viewName then
            self.currentIndex = i
            break
        end
    end

    -- Initialize
    self:setup()

    return self
end

-- Set up touch zones and load initial view
function Display:setup()
    local width, height = self.peripheral.getSize()
    local halfWidth = math.floor(width / 2)

    -- Create touch zones
    self.touchZones = TouchZones.new(self.peripheral)

    -- Left half: previous view
    self.touchZones:addZone("prev", 1, 1, halfWidth, height, function()
        self:previousView()
    end)

    -- Right half: next view
    self.touchZones:addZone("next", halfWidth + 1, 1, width, height, function()
        self:nextView()
    end)

    -- Load initial view
    self:loadView(self.viewName)
end

-- Load a view by name
function Display:loadView(viewName)
    local View = ViewManager.load(viewName)
    if not View then
        print("[!] Failed to load: " .. viewName)
        return false
    end

    self.view = View
    self.viewName = viewName

    -- Create view instance
    local ok, instance = pcall(View.new, self.peripheral, self.viewConfig)
    if ok then
        self.viewInstance = instance
    else
        print("[!] View error: " .. tostring(instance))
        self.viewInstance = nil
        return false
    end

    -- Clear and schedule render
    self.peripheral.clear()
    self:scheduleRender()

    return true
end

-- Go to next view
function Display:nextView()
    self.currentIndex = self.currentIndex + 1
    if self.currentIndex > #self.availableViews then
        self.currentIndex = 1
    end

    local newView = self.availableViews[self.currentIndex]
    print("[*] " .. self.peripheralName .. " -> " .. newView)

    self:loadView(newView)
    self:showIndicator()

    -- Persist change
    Config.updateDisplayView(self.peripheralName, newView)
end

-- Go to previous view
function Display:previousView()
    self.currentIndex = self.currentIndex - 1
    if self.currentIndex < 1 then
        self.currentIndex = #self.availableViews
    end

    local newView = self.availableViews[self.currentIndex]
    print("[*] " .. self.peripheralName .. " -> " .. newView)

    self:loadView(newView)
    self:showIndicator()

    -- Persist change
    Config.updateDisplayView(self.peripheralName, newView)
end

-- Show indicator bar briefly
function Display:showIndicator()
    self.showingIndicator = true

    local width, height = self.peripheral.getSize()
    local viewNum = self.currentIndex .. "/" .. #self.availableViews

    -- Top bar: view name centered
    self.peripheral.setBackgroundColor(colors.blue)
    self.peripheral.setTextColor(colors.white)
    self.peripheral.setCursorPos(1, 1)
    self.peripheral.write(string.rep(" ", width))

    local startX = math.floor((width - #self.viewName) / 2) + 1
    self.peripheral.setCursorPos(math.max(1, startX), 1)
    self.peripheral.write(self.viewName)

    -- View count on right
    self.peripheral.setCursorPos(math.max(1, width - #viewNum + 1), 1)
    self.peripheral.write(viewNum)

    -- Bottom bar: navigation hints
    self.peripheral.setBackgroundColor(colors.gray)
    self.peripheral.setCursorPos(1, height)
    self.peripheral.write(string.rep(" ", width))
    self.peripheral.setCursorPos(1, height)
    self.peripheral.write("< Prev")
    self.peripheral.setCursorPos(width - 5, height)
    self.peripheral.write("Next >")

    -- Reset colors
    self.peripheral.setBackgroundColor(colors.black)
    self.peripheral.setTextColor(colors.white)

    -- Auto-hide after 2 seconds
    self.indicatorTimer = os.startTimer(2)
end

-- Hide indicator and render view
function Display:hideIndicator()
    self.showingIndicator = false
    self.indicatorTimer = nil
    self.peripheral.clear()
    self:render()
end

-- Render the view
function Display:render()
    if not self.viewInstance or self.showingIndicator then
        return
    end

    local ok, err = pcall(self.view.render, self.viewInstance)
    if not ok then
        self.peripheral.setCursorPos(1, 1)
        self.peripheral.setTextColor(colors.red)
        self.peripheral.write("Error: " .. tostring(err):sub(1, 20))
        self.peripheral.setTextColor(colors.white)
    end
end

-- Schedule next render
function Display:scheduleRender()
    local sleepTime = (self.view and self.view.sleepTime) or 1
    self.renderTimer = os.startTimer(sleepTime)
end

-- Handle touch event
function Display:handleTouch(monitorName, x, y)
    if monitorName ~= self.peripheralName then
        return false
    end

    -- If indicator showing, hide it on touch
    if self.showingIndicator then
        self:hideIndicator()
        return true
    end

    -- Route to touch zones
    return self.touchZones:handleTouch(monitorName, x, y)
end

-- Handle timer event
function Display:handleTimer(timerId)
    if timerId == self.indicatorTimer then
        self:hideIndicator()
        return true
    elseif timerId == self.renderTimer then
        self:render()
        self:scheduleRender()
        return true
    end
    return false
end

-- Clear the display
function Display:clear()
    self.peripheral.setBackgroundColor(colors.black)
    self.peripheral.clear()
end

-- Main system run function
function System.run()
    local config = Config.load()

    if #config == 0 then
        print("[!] No displays configured")
        print("    Run: mpm run displays/setup")
        return
    end

    -- Get available views
    print("[*] Scanning views...")
    local availableViews = ViewManager.getMountableViews()

    if #availableViews == 0 then
        print("[!] No views available")
        return
    end

    print("[*] Views: " .. table.concat(availableViews, ", "))
    print("")

    -- Create displays
    local displays = {}
    for _, displayConfig in ipairs(config) do
        local display = Display.new(displayConfig, availableViews)
        if display then
            table.insert(displays, display)
            print("[+] " .. display.peripheralName .. " -> " .. display.viewName)
        end
    end

    if #displays == 0 then
        print("[!] No monitors connected")
        return
    end

    print("")
    print("[*] Touch left/right to switch views")
    print("[*] Press 'q' to quit")
    print("")

    -- Main event loop
    local running = true

    while running do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "key" and p1 == keys.q then
            running = false

        elseif event == "monitor_touch" then
            for _, display in ipairs(displays) do
                if display:handleTouch(p1, p2, p3) then
                    break
                end
            end

        elseif event == "timer" then
            for _, display in ipairs(displays) do
                if display:handleTimer(p1) then
                    break
                end
            end
        end
    end

    -- Cleanup
    for _, display in ipairs(displays) do
        display:clear()
    end

    print("[*] Goodbye!")
end

return System
