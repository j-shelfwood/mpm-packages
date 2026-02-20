-- Paths.lua
-- Centralized file path constants for ShelfOS computers
-- All config file locations defined here to prevent drift
--
-- NOTE: Pocket computer paths are in shelfos-swarm/core/Paths.lua

local Paths = {}

-- Computer paths
Paths.CONFIG = "/shelfos.config"
Paths.LEGACY_CONFIG = "/displays.config"
Paths.RESET_MARKER = "/shelfos.reset"

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
    if fs.exists(Paths.RESET_MARKER) then
        fs.delete(Paths.RESET_MARKER)
    end
end

-- Write reset marker consumed on next boot
function Paths.writeResetMarker(mode)
    local file = fs.open(Paths.RESET_MARKER, "w")
    if not file then
        return false
    end
    file.write(tostring(mode or "clock"))
    file.close()
    return true
end

-- Read + delete reset marker
function Paths.consumeResetMarker()
    if not fs.exists(Paths.RESET_MARKER) then
        return nil
    end
    local file = fs.open(Paths.RESET_MARKER, "r")
    if not file then
        fs.delete(Paths.RESET_MARKER)
        return nil
    end
    local content = file.readAll()
    file.close()
    fs.delete(Paths.RESET_MARKER)
    return content
end

return Paths
