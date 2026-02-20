-- Monitor.lua
-- Single monitor management with settings-button pattern
-- Touch to show settings, click to open view selector
-- Supports view configuration via configSchema
-- Now uses ui/ widgets for consistent styling
--
-- ============================================================================
-- WINDOW BUFFERING ARCHITECTURE (see docs/RENDERING_ARCHITECTURE.md)
-- ============================================================================
-- This module implements flicker-free multi-monitor rendering using the
-- CC:Tweaked window API as a display buffer.
--
-- KEY CONCEPTS:
--   self.peripheral = raw monitor peripheral
--   self.buffer     = window.create() over peripheral (views render here)
--
-- RENDER CYCLE:
--   1. buffer.setVisible(false)   -- hide buffer during render
--   2. buffer.clear()             -- clear invisible buffer
--   3. view.render(viewInstance)  -- view draws to buffer
--   4. buffer.setVisible(true)    -- atomic flip (instant, no flicker)
--
-- WHY THIS WORKS:
--   - Views never see the raw peripheral, only the buffer
--   - All drawing happens to invisible buffer
--   - Single setVisible(true) call flips entire screen atomically
--   - No intermediate states visible = no flicker
--
-- TEXT SCALE:
--   - Set ONCE in initialize() based on monitor physical size
--   - NEVER changed during rendering
--   - Views should NOT call setTextScale()
--
-- INTERACTIVE MENUS:
--   - Config menus use peripheral directly (not buffer)
--   - Needs immediate feedback for touch interactions
--   - Buffer render resumes after menu closes
-- ============================================================================

local ViewManager = mpm('views/Manager')
local ConfigUI = mpm('shelfos/core/ConfigUI')
local MonitorConfigMenu = mpm('shelfos/core/MonitorConfigMenu')
local Theme = mpm('utils/Theme')
local Core = mpm('ui/Core')
local Button = mpm('ui/Button')
local RenderContext = mpm('net/RenderContext')
local DependencyStatus = mpm('net/DependencyStatus')

local Monitor = {}
Monitor.__index = Monitor

local TOUCH_DEBOUNCE_MS = 350
local CONFIG_EXIT_TOUCH_GUARD_MS = 700

local function copyArray(arr)
    local copy = {}
    for i, v in ipairs(arr or {}) do
        copy[i] = v
    end
    return copy
end

-- Calculate optimal text scale based on NATIVE monitor size (at scale 1.0)
-- This prevents feedback loops where changing scale changes dimensions
-- @param monitor The monitor peripheral
-- @return scale, nativeWidth, nativeHeight
local function calculateTextScale(monitor)
    -- Get dimensions at native scale to determine physical monitor size
    monitor.setTextScale(1.0)
    local nativeWidth, nativeHeight = monitor.getSize()

    -- Calculate scale based on native (physical) dimensions
    -- A 2x2 monitor block is ~14x9 at scale 1.0
    -- A 3x3 monitor block is ~29x19 at scale 1.0
    -- A 4x4 monitor block is ~36x25 at scale 1.0
    local pixels = nativeWidth * nativeHeight

    -- Scale 1.0 for all monitor sizes.
    -- Smaller scales (0.5) pack more chars but become hard to read.
    -- Larger scales (2.0+) reduce available chars too much.
    -- GridDisplay handles readability via adaptive column count instead.
    local scale = 1.0

    -- Apply scale
    monitor.setTextScale(scale)

    -- Get final dimensions at this scale
    local width, height = monitor.getSize()

    return scale, width, height
end

-- Create a new monitor manager
-- @param config Monitor configuration from shelfos.config
-- @param onViewChange Callback for view changes
-- @param settings Global settings
-- @param index Monitor index (0-based) for staggering timers
-- @param availableViews Optional precomputed mountable views list
function Monitor.new(config, onViewChange, settings, index, availableViews)
    local self = setmetatable({}, Monitor)

    self.peripheralName = config.peripheral
    self.label = config.label or config.peripheral
    self.viewName = config.view
    self.viewConfig = config.viewConfig or {}
    self.onViewChange = onViewChange
    self.themeName = (settings and settings.theme) or "default"
    self.index = index or 0  -- Used for staggering render timers
    self.renderPhase = self.index * 0.05

    -- Try to connect
    self.peripheral = peripheral.wrap(self.peripheralName)
    self.connected = self.peripheral ~= nil

    if not self.connected then
        return self
    end

    -- State
    self.view = nil
    self.viewInstance = nil
    self.renderTimer = nil
    self.settingsTimer = nil
    self.showingSettings = false
    self.inConfigMenu = false
    self.availableViews = copyArray(availableViews)
    self.currentIndex = 1
    self.settingsButton = nil
    self.pairingMode = false  -- When true, skip rendering (pairing code displayed)
    self.touchDebounceUntil = 0

    -- Window buffer for flicker-free rendering
    self.buffer = nil
    self.bufferWidth = 0
    self.bufferHeight = 0
    self.currentScale = 1.0

    -- Initialize
    self:initialize()

    return self
end

-- Initialize the monitor
function Monitor:initialize()
    if not self.connected then return end

    -- Apply optimal text scale and get dimensions
    self.currentScale, self.bufferWidth, self.bufferHeight = calculateTextScale(self.peripheral)

    -- Create window buffer over the monitor for flicker-free rendering
    -- Window starts visible; we toggle visibility during render cycles
    self.buffer = window.create(self.peripheral, 1, 1, self.bufferWidth, self.bufferHeight, true)

    -- Apply theme palette to both peripheral and buffer
    Theme.apply(self.peripheral, self.themeName)
    Theme.apply(self.buffer, self.themeName)

    -- Get available views. Prefer the precomputed list from Kernel to avoid
    -- repeated mount scans during multi-monitor boot.
    if #self.availableViews == 0 then
        self.availableViews = ViewManager.getSelectableViews()
    end

    -- Find current view index
    for i, name in ipairs(self.availableViews) do
        if name == self.viewName then
            self.currentIndex = i
            break
        end
    end

    -- Load initial view
    self:loadView(self.viewName)
end

-- Handle monitor resize event (blocks added/removed)
function Monitor:handleResize()
    if not self.connected then return end

    -- Guard against resize loops from setTextScale
    if self.handlingResize then return end
    self.handlingResize = true

    -- Recalculate optimal text scale and get new dimensions
    self.currentScale, self.bufferWidth, self.bufferHeight = calculateTextScale(self.peripheral)

    -- Recreate window buffer with new dimensions
    self.buffer = window.create(self.peripheral, 1, 1, self.bufferWidth, self.bufferHeight, true)

    -- Reapply theme to both peripheral and buffer
    Theme.apply(self.peripheral, self.themeName)
    Theme.apply(self.buffer, self.themeName)

    -- Reload view to recalculate layout
    if self.viewName then
        self:loadView(self.viewName)
    end

    self.handlingResize = false
end

-- Load a view by name
function Monitor:loadView(viewName)
    if not self.connected then return false end

    local View = ViewManager.load(viewName)
    if not View then
        print("[Monitor] Failed to load: " .. viewName)
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

    -- Create view instance with BUFFER (not raw peripheral)
    -- This enables flicker-free rendering via window API
    -- Pass peripheral name for overlay event filtering
    local ok, instance = pcall(View.new, self.buffer, self.viewConfig, self.peripheralName)
    if ok then
        self.viewInstance = instance
    else
        print("[Monitor] View error: " .. tostring(instance))
        self.viewInstance = nil
        return false
    end

    -- Initial render (buffer handles flicker prevention)
    self:render()
    self:scheduleRender(self.renderPhase)  -- 50ms stagger per monitor

    return true
end

-- Draw settings button using ui/Button (renders to buffer)
function Monitor:drawSettingsButton()
    -- Button in bottom-right with padding
    local buttonLabel = "[*]"
    local buttonX = self.bufferWidth - #buttonLabel - 2  -- padding from edge
    local buttonY = self.bufferHeight - 1                 -- 1 row padding from bottom

    -- Ensure minimum position
    buttonX = math.max(1, buttonX)
    buttonY = math.max(1, buttonY)

    -- Create button using ui/Button (renders to buffer)
    self.settingsButton = Button.neutral(self.buffer, buttonX, buttonY, buttonLabel, nil, {
        padding = 1
    })
    self.settingsButton:render()

    self.showingSettings = true

    -- Reset hide timer only when explicitly requested by touch interaction.
    -- Render-path redraws should not extend button lifetime indefinitely.
    if self.settingsTimer then
        os.cancelTimer(self.settingsTimer)
    end
    self.settingsTimer = os.startTimer(3)
end

-- Hide settings button
function Monitor:hideSettingsButton()
    self.showingSettings = false
    self.settingsTimer = nil
    self.settingsButton = nil
end

-- Check if touch is on settings button
function Monitor:isSettingsButtonTouch(x, y)
    if not self.settingsButton then return false end
    return self.settingsButton:contains(x, y)
end

-- Open config menu (uses MonitorConfigMenu for UI)
function Monitor:openConfigMenu()
    if self.inConfigMenu then
        return
    end

    self.touchDebounceUntil = os.epoch("utc") + TOUCH_DEBOUNCE_MS
    self.inConfigMenu = true
    self.showingSettings = false
    self.settingsButton = nil

    -- Cancel pending timers
    if self.renderTimer then
        os.cancelTimer(self.renderTimer)
        self.renderTimer = nil
    end
    if self.settingsTimer then
        os.cancelTimer(self.settingsTimer)
        self.settingsTimer = nil
    end

    -- Hide buffered window while drawing interactive config UI directly
    -- on the raw peripheral to avoid stale-buffer interference.
    if self.buffer then
        self.buffer.setVisible(false)
    end

    -- Show view selection + optional config flow
    local ok, selectedView, newConfig = pcall(MonitorConfigMenu.openConfigFlow, self)
    local didLoadView = false

    if not ok then
        print("[Monitor] Config menu error on " .. (self.peripheralName or "unknown") .. ": " .. tostring(selectedView))
    elseif selectedView then
        local pendingConfig = newConfig or {}
        local previousConfig = self.viewConfig
        self.viewConfig = pendingConfig
        didLoadView = self:loadView(selectedView) and true or false
        if didLoadView and self.onViewChange then
            self.onViewChange(self.peripheralName, selectedView, self.viewConfig)
        elseif not didLoadView then
            self.viewConfig = previousConfig
        end
    end

    self:closeConfigMenu(didLoadView)
end

-- Close config menu
function Monitor:closeConfigMenu(skipImmediateRender)
    self.inConfigMenu = false
    self.touchDebounceUntil = os.epoch("utc") + CONFIG_EXIT_TOUCH_GUARD_MS
    if self.buffer then
        self.buffer.setVisible(true)
    end
    -- Clear peripheral and always resume buffered rendering immediately.
    -- loadView() can run while inConfigMenu=true, which suppresses its internal
    -- render/schedule path; therefore close must always re-prime the render loop.
    self.peripheral.clear()
    self:render()
    self:scheduleRender()
end

-- Render the view using window buffering for flicker-free updates
-- ============================================================================
-- TWO-PHASE RENDERING (see docs/RENDERING_ARCHITECTURE.md)
-- ============================================================================
-- Phase 1: getData() - CAN yield, buffer stays VISIBLE
--          Other monitor timers can fire during yields
-- Phase 2: renderWithData() - NO yields, buffer HIDDEN
--          Drawing happens atomically, then buffer flipped visible
-- ============================================================================
function Monitor:render()
    if self.inConfigMenu or not self.viewInstance then
        return
    end

    -- ========================================================================
    -- PHASE 1: Fetch data (may yield - buffer stays VISIBLE)
    -- ========================================================================
    -- This allows other monitor timers to fire and render while we wait.
    -- Yields in getData() won't cause other monitors to see a blank screen.
    local data, dataErr
    local getDataOk = true
    local contextKey = (self.peripheralName or "unknown") .. "|" .. (self.viewName or "unknown")

    if self.view.getData then
        -- New two-phase API
        RenderContext.set(contextKey)
        getDataOk, dataErr = pcall(function()
            data = self.view.getData(self.viewInstance)
        end)
        RenderContext.clear()
    end

    -- ========================================================================
    -- PHASE 2: Draw to buffer (no yields - buffer HIDDEN)
    -- ========================================================================
    -- Hide buffer, clear, render, then atomic flip.
    -- All drawing happens to invisible buffer for flicker-free updates.
    self.buffer.setVisible(false)
    self.buffer.setBackgroundColor(colors.black)
    self.buffer.clear()

    if not getDataOk then
        -- Log full error to terminal
        print("[Monitor] getData error in " .. (self.viewName or "unknown") .. ": " .. tostring(dataErr))

        -- Use view's error renderer if available
        if self.view.renderError then
            pcall(self.view.renderError, self.viewInstance, tostring(dataErr))
        else
            -- Fallback error display
            self.buffer.setCursorPos(1, 1)
            self.buffer.setTextColor(colors.red)
            self.buffer.write("Data Error")

            if self.bufferHeight >= 3 and dataErr then
                self.buffer.setCursorPos(1, 3)
                self.buffer.setTextColor(colors.gray)
                local errStr = tostring(dataErr):sub(1, self.bufferWidth)
                self.buffer.write(errStr)
            end
            self.buffer.setTextColor(colors.white)
        end
    else
        -- Render content with fetched data
        local renderOk, renderErr

        if self.view.renderWithData then
            -- New two-phase API
            renderOk, renderErr = pcall(self.view.renderWithData, self.viewInstance, data)
        else
            -- Legacy: view.render does both getData and draw
            -- This path yields while buffer hidden (breaks multi-monitor)
            renderOk, renderErr = pcall(self.view.render, self.viewInstance)
        end

        if not renderOk then
            print("[Monitor] Render error in " .. (self.viewName or "unknown") .. ": " .. tostring(renderErr))

            self.buffer.setCursorPos(1, 1)
            self.buffer.setTextColor(colors.red)
            self.buffer.write("Render Error")

            if self.bufferHeight >= 3 and renderErr then
                self.buffer.setCursorPos(1, 3)
                self.buffer.setTextColor(colors.gray)
                local errStr = tostring(renderErr):sub(1, self.bufferWidth)
                self.buffer.write(errStr)
            end
            self.buffer.setTextColor(colors.white)
        end
    end

    -- Redraw settings button if showing (on buffer)
    if self.showingSettings and self.settingsButton then
        self.settingsButton:render()
    end

    -- Dependency health dots (remote peripheral status per view context)
    self:drawDependencyStatus(contextKey)

    -- Atomic flip: show buffer (instant, no flicker)
    self.buffer.setVisible(true)
end

-- Draw remote dependency status dots on the bottom row
-- One dot per remote peripheral touched by this monitor/view context:
--   green=healthy, orange=refreshing/stale, red=error/disconnected
function Monitor:drawDependencyStatus(contextKey)
    if not self.buffer or not contextKey then
        return
    end

    local deps = DependencyStatus.getContext(contextKey)
    if not deps or #deps == 0 then
        return
    end

    local y = self.bufferHeight
    local maxDots = math.max(1, self.bufferWidth - 1)
    local count = math.min(#deps, maxDots)

    self.buffer.setBackgroundColor(colors.black)
    for i = 1, count do
        local dep = deps[i]
        local color = colors.lime
        if dep.state == "pending" then
            color = colors.orange
        elseif dep.state == "error" then
            color = colors.red
        end

        self.buffer.setCursorPos(i, y)
        self.buffer.setTextColor(color)
        self.buffer.write(".")
    end

    if #deps > count then
        self.buffer.setCursorPos(math.min(self.bufferWidth, count + 1), y)
        self.buffer.setTextColor(colors.lightGray)
        self.buffer.write("+")
    end

    self.buffer.setTextColor(colors.white)
end

-- Schedule next render
-- @param offset Optional time offset to stagger initial renders (default 0)
function Monitor:scheduleRender(offset)
    if self.inConfigMenu then return end
    -- Cancel any existing render timer to prevent orphaned timers
    if self.renderTimer then
        os.cancelTimer(self.renderTimer)
    end
    local sleepTime = (self.view and self.view.sleepTime) or 1
    local phase = offset
    if phase == nil then
        phase = self.renderPhase or 0
    end
    self.renderTimer = os.startTimer(sleepTime + phase)
end

-- Handle touch event
function Monitor:handleTouch(monitorName, x, y)
    if monitorName ~= self.peripheralName then
        return false
    end

    if self.pairingMode then
        return false
    end

    -- Config menu is now handled synchronously in openConfigMenu
    if self.inConfigMenu then
        return false
    end

    local now = os.epoch("utc")
    if now < (self.touchDebounceUntil or 0) then
        return true
    end

    -- Header touch (y=1) always opens view selector
    -- This ensures users can always change views, even with interactive views
    if y == 1 then
        self:openConfigMenu()
        return true
    end

    -- Check for settings button click
    if self.showingSettings and self:isSettingsButtonTouch(x, y) then
        self:openConfigMenu()
        return true
    end

    -- Show settings affordance immediately on body touches so first-tap feedback
    -- is constant-time even when interactive views have heavy touch handlers.
    self:drawSettingsButton()

    -- Forward touch to view if it supports handleTouch (interactive views)
    -- View can handle touch for item selection, scrolling, etc.
    if self.view and self.view.handleTouch and self.viewInstance then
        local ok, handled = pcall(self.view.handleTouch, self.viewInstance, x, y)
        if not ok then
            print("[Monitor] Touch handler error on " .. (self.peripheralName or "unknown") .. ": " .. tostring(handled))
            handled = false
        end
        if handled then
            -- Re-render immediately to show updated state
            self:render()
        end
    end

    return true
end

-- Handle timer event
function Monitor:handleTimer(timerId)
    if timerId == self.settingsTimer then
        self:hideSettingsButton()
        return true
    elseif timerId == self.renderTimer then
        -- Protect render with pcall to ensure scheduleRender is always called
        local ok, err = pcall(function()
            self:render()
        end)
        if not ok then
            print("[Monitor] Render error on " .. (self.peripheralName or "unknown") .. ": " .. tostring(err))
        end
        -- Always schedule next render to keep the loop alive
        self:scheduleRender()
        return true
    end
    return false
end

-- Check if this is our render timer (for Kernel compatibility)
function Monitor:isRenderTimer(timerId)
    return timerId == self.renderTimer or timerId == self.settingsTimer
end

-- Clear the monitor (both buffer and peripheral)
function Monitor:clear()
    if self.connected then
        if self.buffer then
            Core.clear(self.buffer)
        end
        Core.clear(self.peripheral)
    end
end

-- Check if monitor is connected
function Monitor:isConnected()
    return self.connected
end

-- Get monitor name
function Monitor:getName()
    return self.label
end

-- Get peripheral name
function Monitor:getPeripheralName()
    return self.peripheralName
end

-- Get current view name
function Monitor:getViewName()
    return self.viewName or "none"
end

-- Get view configuration
function Monitor:getViewConfig()
    return self.viewConfig
end

-- Update view configuration
function Monitor:setViewConfig(key, value)
    self.viewConfig[key] = value

    if self.viewInstance and self.view and self.view.onConfigChange then
        pcall(self.view.onConfigChange, self.viewInstance, key, value)
    end
end

-- Reconnect to peripheral
function Monitor:reconnect()
    self.peripheral = peripheral.wrap(self.peripheralName)
    self.connected = self.peripheral ~= nil

    if self.connected then
        self:initialize()
    end

    return self.connected
end

-- Set theme for this monitor
function Monitor:setTheme(themeName)
    self.themeName = themeName or "default"
    if self.connected then
        Theme.apply(self.peripheral, self.themeName)
        if self.buffer then
            Theme.apply(self.buffer, self.themeName)
        end
        -- Re-render to show updated colors
        if not self.inConfigMenu and self.viewInstance then
            self:render()
        end
    end
end

-- Get current theme name
function Monitor:getTheme()
    return self.themeName
end

-- ============================================================================
-- PAIRING MODE
-- ============================================================================
-- When pairing mode is active, monitors skip rendering to allow the pairing
-- code to remain visible on screen. The Kernel sets this when entering
-- the "Accept from pocket" pairing flow.
-- ============================================================================

-- Set pairing mode (pauses rendering while pairing code is displayed)
-- @param enabled boolean
function Monitor:setPairingMode(enabled)
    self.pairingMode = enabled
end

-- ============================================================================
-- INDEPENDENT EVENT LOOP
-- ============================================================================
-- This method runs in its own coroutine via parallel.waitForAny
-- Each monitor gets its OWN copy of the event queue (CC:Tweaked parallel API)
-- This means monitors can block (e.g., for config menus) without affecting others
-- ============================================================================

-- Run the monitor's independent event loop
-- @param running Reference to shared running flag (table with .value)
function Monitor:runLoop(running)
    if not self.connected then
        return
    end

    -- Initial render and schedule (only if not in pairing mode)
    if self.viewInstance and not self.pairingMode then
        self:render()
        self:scheduleRender()
    end

    while running.value do
        -- Wait for ANY event - we filter ourselves
        -- This is safe because parallel gives us our own event queue copy
        local event, p1, p2, p3 = os.pullEvent()

        if event == "timer" then
            self:handleTimer(p1)

        elseif event == "monitor_touch" then
            self:handleTouch(p1, p2, p3)

        elseif event == "monitor_resize" then
            -- Only handle resize for our peripheral
            if p1 == self.peripheralName then
                self:handleResize()
            end
        end
        -- Other events are ignored by this monitor's loop
    end
end

return Monitor
