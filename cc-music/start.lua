-- cc-music entrypoint
-- Run with: mpm run cc-music [url-or-search-term]
local args = {...}
shell.run("/mpm/Packages/cc-music/music.lua", table.unpack(args))
