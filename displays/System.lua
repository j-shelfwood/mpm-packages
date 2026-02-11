-- System.lua
-- Display management with simple settings button pattern
-- Touch to show settings icon, click icon to configure

local Config = mpm('displays/Config')
local ViewManager = mpm('views/Manager')

local System = {}

-- Display class
local Display = {}
Display.__index = Display

-- Calculate optimal text scale based on monitor size
-- Returns scale that makes UI elements appropriately sized
local function calculateTextScale(width, height)
    -- CC:Tweaked supports 0.5 to 5 in 0.5 increments
    local pixels = width * height

    if pixels >= 800 then
        return 1.0  -- Large monitor: normal scale
    elseif pixels >= 400 then
        return 1.0  -- Medium: normal scale
    elseif pixels >= 150 then
        return 0.5  -- Small: half scale for more room
    else
        return 0.5  -- Very small: minimum scale
    end
end

function Display.new(config, availableViews)
    local self = setmetatable({}, Display)

    self.peripheralName = config.monitor
    self.peripheral = peripheral.wrap(self.peripheralName)

    if not self.peripheral then
        return nil
    end

    -- Apply optimal text scale
    local width, height = self.peripheral.getSize()
    local scale = calculateTextScale(width, height)
    self.peripheral.setTextScale(scale)

    self.availableViews = availableViews
    self.currentIndex = 1
    self.viewName = config.view
    self.viewConfig = config.config or {}

    self.view = nil
    self.viewInstance = nil
    self.renderTimer = nil
    self.settingsTimer = nil
    self.showingSettings = false
    self.inConfigMenu = false

    -- Find initial view index
    for i, name in ipairs(availableViews) do
        if name == self.viewName then
            self.currentIndex = i
            break
        end
    end

    -- Load initial view
    self:loadView(self.viewName)

    return self
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

    -- Update index
    for i, name in ipairs(self.availableViews) do
        if name == viewName then
            self.currentIndex = i
            break
        end
    end

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

-- Draw settings button with padding in bottom-right corner
function Display:drawSettingsButton()
    local width, height = self.peripheral.getSize()

    -- Save state
    local oldBg = self.peripheral.getBackgroundColor()
    local oldFg = self.peripheral.getTextColor()

    -- Button with padding: " [*] " with 1 char margin from edges
    local buttonText = " [*] "
    local buttonX = width - #buttonText - 1  -- 1 char padding from right
    local buttonY = height - 1               -- 1 row padding from bottom

    -- Ensure minimum position
    buttonX = math.max(1, buttonX)
    buttonY = math.max(1, buttonY)

    self.peripheral.setBackgroundColor(colors.blue)
    self.peripheral.setTextColor(colors.white)
    self.peripheral.setCursorPos(buttonX, buttonY)
    self.peripheral.write(buttonText)

    -- Restore
    self.peripheral.setBackgroundColor(oldBg)
    self.peripheral.setTextColor(oldFg)

    self.showingSettings = true
    self.settingsTimer = os.startTimer(3)

    -- Store button bounds for hit detection
    self.settingsButtonBounds = {
        x1 = buttonX,
        y1 = buttonY,
        x2 = buttonX + #buttonText - 1,
        y2 = buttonY
    }
end

-- Hide settings button
function Display:hideSettingsButton()
    self.showingSettings = false
    self.settingsTimer = nil
    self.settingsButtonBounds = nil
end

-- Check if touch is on settings button
function Display:isSettingsButtonTouch(x, y)
    if not self.settingsButtonBounds then return false end

    local b = self.settingsButtonBounds
    return x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2
end

-- Draw the configuration menu
function Display:drawConfigMenu()
    local width, height = self.peripheral.getSize()

    self.peripheral.setBackgroundColor(colors.black)
    self.peripheral.clear()

    -- Title
    self.peripheral.setBackgroundColor(colors.blue)
    self.peripheral.setTextColor(colors.white)
    self.peripheral.setCursorPos(1, 1)
    self.peripheral.write(string.rep(" ", width))
    local title = "Select View"
    self.peripheral.setCursorPos(math.floor((width - #title) / 2) + 1, 1)
    self.peripheral.write(title)

    -- View list
    self.peripheral.setBackgroundColor(colors.black)
    local startY = 3
    local maxItems = height - 4  -- Leave room for title and cancel

    for i, viewName in ipairs(self.availableViews) do
        if i <= maxItems then
            local y = startY + i - 1

            if i == self.currentIndex then
                -- Highlighted (current)
                self.peripheral.setBackgroundColor(colors.gray)
                self.peripheral.setTextColor(colors.white)
                self.peripheral.setCursorPos(1, y)
                self.peripheral.write(string.rep(" ", width))
                self.peripheral.setCursorPos(2, y)
                self.peripheral.write("> " .. viewName)
            else
                self.peripheral.setBackgroundColor(colors.black)
                self.peripheral.setTextColor(colors.lightGray)
                self.peripheral.setCursorPos(2, y)
                self.peripheral.write("  " .. viewName)
            end
        end
    end

    -- Cancel button at bottom
    self.peripheral.setBackgroundColor(colors.red)
    self.peripheral.setTextColor(colors.white)
    self.peripheral.setCursorPos(1, height)
    self.peripheral.write(string.rep(" ", width))
    local cancelText = "[ Cancel ]"
    self.peripheral.setCursorPos(math.floor((width - #cancelText) / 2) + 1, height)
    self.peripheral.write(cancelText)

    self.peripheral.setBackgroundColor(colors.black)
    self.peripheral.setTextColor(colors.white)
end

-- Handle touch in config menu
-- Returns: nil (stay in menu), "cancel", or view name
function Display:handleConfigMenuTouch(x, y)
    local width, height = self.peripheral.getSize()

    -- Cancel button (bottom row)
    if y == height then
        return "cancel"
    end

    -- View selection (rows 3 to height-1)
    local startY = 3
    local maxItems = height - 4
    local touchedIndex = y - startY + 1

    if touchedIndex >= 1 and touchedIndex <= #self.availableViews and touchedIndex <= maxItems then
        return self.availableViews[touchedIndex]
    end

    return nil
end

-- Open config menu
function Display:openConfigMenu()
    self.inConfigMenu = true
    self.showingSettings = false

    -- Cancel any pending timers
    if self.renderTimer then
        os.cancelTimer(self.renderTimer)
        self.renderTimer = nil
    end
    if self.settingsTimer then
        os.cancelTimer(self.settingsTimer)
        self.settingsTimer = nil
    end

    self:drawConfigMenu()
end

-- Close config menu and resume view
function Display:closeConfigMenu()
    self.inConfigMenu = false
    self.peripheral.clear()
    self:scheduleRender()
end

-- Render the view
function Display:render()
    if self.inConfigMenu or not self.viewInstance then
        return
    end

    local ok, err = pcall(self.view.render, self.viewInstance)
    if not ok then
        self.peripheral.setCursorPos(1, 1)
        self.peripheral.setTextColor(colors.red)
        self.peripheral.write("Error: " .. tostring(err):sub(1, 20))
        self.peripheral.setTextColor(colors.white)
    end

    -- Redraw settings button if showing
    if self.showingSettings then
        self:drawSettingsButton()
    end
end

-- Schedule next render
function Display:scheduleRender()
    if self.inConfigMenu then return end
    local sleepTime = (self.view and self.view.sleepTime) or 1
    self.renderTimer = os.startTimer(sleepTime)
end

-- Handle touch event
function Display:handleTouch(monitorName, x, y)
    if monitorName ~= self.peripheralName then
        return false
    end

    -- Config menu mode
    if self.inConfigMenu then
        local result = self:handleConfigMenuTouch(x, y)

        if result == "cancel" then
            self:closeConfigMenu()
        elseif result then
            -- Selected a view
            print("[*] " .. self.peripheralName .. " -> " .. result)
            Config.updateDisplayView(self.peripheralName, result)
            self:loadView(result)
            self:closeConfigMenu()
        end

        return true
    end

    -- Normal mode: check for settings button click
    if self.showingSettings and self:isSettingsButtonTouch(x, y) then
        self:openConfigMenu()
        return true
    end

    -- Any other touch: show settings button
    self:drawSettingsButton()
    return true
end

-- Handle timer event
function Display:handleTimer(timerId)
    if timerId == self.settingsTimer then
        self:hideSettingsButton()
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
    print("[*] Touch monitor to show settings")
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
