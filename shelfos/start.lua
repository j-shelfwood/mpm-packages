-- ShelfOS - Base Information System
-- Entry point: mpm run shelfos

local Kernel = mpm('shelfos/core/Kernel')
local kernel = Kernel.new()

if kernel:boot() then
    kernel:run()
end
