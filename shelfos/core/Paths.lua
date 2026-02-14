-- Paths.lua
-- Centralized file path constants for ShelfOS computers
-- All config file locations defined here to prevent drift
--
-- NOTE: Pocket computer paths are in shelfos-swarm/core/Paths.lua

local Paths = {}

-- Computer paths
Paths.CONFIG = "/shelfos.config"
Paths.LEGACY_CONFIG = "/displays.config"

-- Get config path
function Paths.getConfig()
    return Paths.CONFIG
end

-- Delete all config files (for factory reset)
function Paths.deleteFiles()
    if fs.exists(Paths.CONFIG) then
        fs.delete(Paths.CONFIG)
    end
    if fs.exists(Paths.LEGACY_CONFIG) then
        fs.delete(Paths.LEGACY_CONFIG)
    end
end

return Paths
