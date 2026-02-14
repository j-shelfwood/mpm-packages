-- ShelfOS Swarm - Pocket Computer Controller
-- Entry point: mpm run shelfos-swarm
--
-- The pocket computer acts as the "queen" of the swarm.
-- All swarm computers must pair with it to join the network.

-- Check if running on pocket computer
if not pocket then
    print("[!] ShelfOS Swarm requires a pocket computer")
    print("")
    print("For swarm computers, use: mpm run shelfos")
    return
end

local App = mpm('shelfos-swarm/App')

local app = App.new()
local ok = app:init()

if ok then
    app:run()
end
