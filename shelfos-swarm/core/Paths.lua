-- Paths.lua
-- Centralized file path constants for shelfos-swarm (pocket)

local Paths = {}

-- Swarm authority data
Paths.REGISTRY = "/swarm_registry.dat"
Paths.IDENTITY = "/swarm_identity.dat"

-- Legacy paths (for migration)
Paths.LEGACY_SECRET = "/shelfos_secret.txt"
Paths.LEGACY_CONFIG = "/shelfos_pocket.config"

-- Delete all swarm files
function Paths.deleteAll()
    local files = {
        Paths.REGISTRY,
        Paths.IDENTITY,
        Paths.LEGACY_SECRET,
        Paths.LEGACY_CONFIG
    }
    for _, path in ipairs(files) do
        if fs.exists(path) then
            fs.delete(path)
        end
    end
end

-- Check if legacy data exists (for migration)
function Paths.hasLegacyData()
    return fs.exists(Paths.LEGACY_SECRET)
end

return Paths
