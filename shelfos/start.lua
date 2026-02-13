-- ShelfOS - Base Information System
-- Entry point: mpm run shelfos [mode]
--
-- Modes:
--   (default)  - Auto-detect: pocket, display, or headless
--   pocket     - Pocket computer companion app
--   display    - Force display mode (requires monitors)
--   headless   - Force headless mode (peripheral host)
--   host       - Alias for headless

local args = {...}
local mode = args[1]

-- Detect mode if not specified
if not mode then
    -- Check if pocket computer (has pocket API)
    if pocket then
        mode = "pocket"
    else
        -- Check for monitors
        local monitors = {peripheral.find("monitor")}
        if #monitors > 0 then
            mode = "display"
        else
            mode = "headless"
        end
    end
end

-- Normalize mode aliases
if mode == "host" then
    mode = "headless"
end

-- Run appropriate mode
if mode == "pocket" then
    -- Pocket computer companion
    local App = mpm('shelfos/pocket/App')
    local app = App.new()
    app:run()
elseif mode == "headless" then
    -- Peripheral host mode
    local headless = mpm('shelfos/modes/headless')
    headless.run()
else
    -- Display mode (default)
    local Kernel = mpm('shelfos/core/Kernel')
    local kernel = Kernel.new()

    if kernel:boot() then
        kernel:run()
    end
end
