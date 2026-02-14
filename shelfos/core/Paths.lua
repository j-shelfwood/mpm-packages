-- Paths.lua
-- Centralized file path constants for ShelfOS zone computers
-- All config file locations defined here to prevent drift
--
-- NOTE: Pocket computer paths are in shelfos-swarm/core/Paths.lua

local Paths = {}

-- Zone computer paths
Paths.ZONE_CONFIG = "/shelfos.config"
Paths.LEGACY_CONFIG = "/displays.config"

-- Get zone config path
function Paths.getZoneConfig()
    return Paths.ZONE_CONFIG
end

-- Delete all zone files (for factory reset)
function Paths.deleteZoneFiles()
    if fs.exists(Paths.ZONE_CONFIG) then
        fs.delete(Paths.ZONE_CONFIG)
    end
    if fs.exists(Paths.LEGACY_CONFIG) then
        fs.delete(Paths.LEGACY_CONFIG)
    end
end

return Paths
