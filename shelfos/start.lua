-- ShelfOS - Base Information System
-- Entry point: mpm run shelfos

local Kernel = mpm('shelfos/core/Kernel')

-- Parse command line arguments
local args = {...}
local command = args[1]

if command == "setup" then
    -- Run setup wizard
    local setup = mpm('shelfos/tools/setup')
    setup.run()
elseif command == "migrate" then
    -- Migrate from legacy displays
    local migrate = mpm('shelfos/tools/migrate')
    migrate.run()
else
    -- Normal startup
    local kernel = Kernel.new()
    kernel:boot()
    kernel:run()
end
