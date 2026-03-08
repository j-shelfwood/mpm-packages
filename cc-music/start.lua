-- cc-music entrypoint
-- Run with: mpm run cc-music [url-or-search-term]
local args = {...}

-- Build a proper require for music.lua — shell injects require per-program
-- but mpm's loadfile+setfenv env doesn't have it. cc/require.lua handles
-- this same problem on line 27 with: require and require(...) or dofile(...)
local cc_require = require and require("cc.require") or dofile("/rom/modules/main/cc/require.lua")

local fn, err = loadfile("/mpm/Packages/cc-music/music.lua")
if not fn then error("cc-music: " .. tostring(err)) end

local env = setmetatable({}, { __index = _ENV })
env.require, env.package = cc_require.make(env, "/mpm/Packages/cc-music")
setfenv(fn, env)

fn(table.unpack(args))
