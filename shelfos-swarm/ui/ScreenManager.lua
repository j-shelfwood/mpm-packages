-- ScreenManager.lua
-- Push/pop screen navigation for shelfos-swarm pocket computer
-- Manages screen stack, event routing, and context passing
--
-- Screen contract:
--   screen.draw(ctx)                    -- Render screen content (required)
--   screen.handleEvent(ctx, event, ...) -- Handle events, return action string or nil (required)
--   screen.onEnter(ctx, args)           -- Called when screen becomes active (optional)
--   screen.onExit(ctx)                  -- Called when screen is popped (optional)
--
-- Actions returned from handleEvent:
--   "pop"          - Pop this screen (return to parent)
--   "quit"         - Quit the entire app
--   {push = screen, args = ...}  - Push a new screen
--   {replace = screen, args = ...} - Replace current screen
--   nil            - No action (continue event loop)

local TermUI = mpm('ui/TermUI')

local ScreenManager = {}
ScreenManager.__index = ScreenManager

-- Create a new screen manager
-- @param app App instance (provides SwarmAuthority, modem state, etc.)
-- @return ScreenManager instance
function ScreenManager.new(app)
    local self = setmetatable({}, ScreenManager)
    self.app = app
    self.stack = {}
    self.running = false
    self.ctx = nil

    return self
end

-- Build context object for screens
-- @return ctx table
function ScreenManager:buildContext()
    local w, h = TermUI.getSize()
    return {
        app = self.app,
        manager = self,
        width = w,
        height = h
    }
end

-- Push a new screen onto the stack
-- @param screen Screen module table
-- @param args Optional arguments for onEnter
function ScreenManager:push(screen, args)
    -- Exit current screen if any
    local current = self:current()
    if current and current.onExit then
        current.onExit(self.ctx)
    end

    -- Push new screen
    table.insert(self.stack, screen)

    -- Enter new screen
    self.ctx = self:buildContext()
    if screen.onEnter then
        screen.onEnter(self.ctx, args)
    end

    -- Redraw
    self:redraw()
end

-- Pop the current screen
-- @param result Optional result to pass back (currently unused, for future)
function ScreenManager:pop(result)
    if #self.stack <= 1 then
        -- Last screen: quit
        self.running = false
        return
    end

    -- Exit current screen
    local current = self:current()
    if current and current.onExit then
        current.onExit(self.ctx)
    end

    -- Pop
    table.remove(self.stack)

    -- Re-enter parent screen
    local parent = self:current()
    self.ctx = self:buildContext()
    if parent and parent.onResume then
        parent.onResume(self.ctx, result)
    end

    -- Redraw
    self:redraw()
end

-- Replace current screen with a new one
-- @param screen Screen module table
-- @param args Optional arguments for onEnter
function ScreenManager:replace(screen, args)
    -- Exit current screen
    local current = self:current()
    if current and current.onExit then
        current.onExit(self.ctx)
    end

    -- Replace top of stack
    if #self.stack > 0 then
        self.stack[#self.stack] = screen
    else
        table.insert(self.stack, screen)
    end

    -- Enter new screen
    self.ctx = self:buildContext()
    if screen.onEnter then
        screen.onEnter(self.ctx, args)
    end

    -- Redraw
    self:redraw()
end

-- Get current (top) screen
-- @return screen or nil
function ScreenManager:current()
    if #self.stack > 0 then
        return self.stack[#self.stack]
    end
    return nil
end

-- Redraw current screen
function ScreenManager:redraw()
    local screen = self:current()
    if screen and screen.draw then
        screen.draw(self.ctx)
    end
end

-- Process an action returned by handleEvent
-- @param action The action to process
function ScreenManager:processAction(action)
    if action == "pop" then
        self:pop()
    elseif action == "quit" then
        self.running = false
    elseif type(action) == "table" then
        if action.push then
            self:push(action.push, action.args)
        elseif action.replace then
            self:replace(action.replace, action.args)
        end
    end
    -- nil = no action, continue
end

-- Main event loop
-- Runs until no screens remain or "quit" action received
function ScreenManager:run()
    self.running = true
    self.ctx = self:buildContext()

    -- Initial draw
    self:redraw()

    while self.running and #self.stack > 0 do
        local screen = self:current()
        if not screen then break end

        -- Wait for any event
        local event = { os.pullEvent() }

        -- Route to current screen
        if screen.handleEvent then
            local action = screen.handleEvent(self.ctx, table.unpack(event))
            if action then
                self:processAction(action)
            end
        end
    end
end

return ScreenManager
