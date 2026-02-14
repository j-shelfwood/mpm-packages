-- Paths.lua
-- Centralized file path constants for ShelfOS
-- All config file locations defined here to prevent drift

local Paths = {}

-- Zone computer paths
Paths.ZONE_CONFIG = "/shelfos.config"
Paths.LEGACY_CONFIG = "/displays.config"

-- Pocket computer paths
Paths.POCKET_SECRET = "/shelfos_secret.txt"
Paths.POCKET_CONFIG = "/shelfos_pocket.config"

-- Get zone config path (alias for compatibility with Config.lua)
function Paths.getZoneConfig()
    return Paths.ZONE_CONFIG
end

-- Get pocket secret path
function Paths.getPocketSecret()
    return Paths.POCKET_SECRET
end

-- Get pocket config path
function Paths.getPocketConfig()
    return Paths.POCKET_CONFIG
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

-- Delete all pocket files (for leave swarm)
function Paths.deletePocketFiles()
    if fs.exists(Paths.POCKET_SECRET) then
        fs.delete(Paths.POCKET_SECRET)
    end
    if fs.exists(Paths.POCKET_CONFIG) then
        fs.delete(Paths.POCKET_CONFIG)
    end
end

return Paths
