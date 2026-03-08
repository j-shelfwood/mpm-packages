-- cc-music entrypoint
-- Run with: mpm run cc-music [url-or-search-term]
local args = {...}
local fn = loadfile("/mpm/Packages/cc-music/music.lua")
if fn then
    fn(table.unpack(args))
else
    error("cc-music: could not load music.lua")
end
