-- ShelfOS - Base Information System
-- Entry point: mpm run shelfos [mode]
--
-- Modes:
--   (default)  - Boot ShelfOS kernel
--   pocket     - Pocket computer companion app

local args = {...}
local mode = args[1]

-- Auto-pocket detection
if not mode and pocket then
    mode = "pocket"
end

-- Run appropriate mode
if mode == "pocket" then
    -- Redirect to shelfos-swarm (pocket is swarm controller)
    print("[ShelfOS] Pocket computer detected")
    print("")
    print("Use: mpm run shelfos-swarm")
    print("")
    print("The pocket computer is the swarm controller.")
    print("Computers use: mpm run shelfos")
    return
else
    -- Unified kernel mode (works with or without monitors)
    while true do
        local Kernel = mpm('shelfos/core/Kernel')
        local kernel = Kernel.new()

        if kernel:boot() then
            local ok, err = pcall(kernel.run, kernel)
            if not ok then
                print("[ShelfOS] Fatal error: " .. tostring(err))
            end
        end

        print("[ShelfOS] Restarting in 3 seconds...")
        os.sleep(3)
    end
end
