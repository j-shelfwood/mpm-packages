-- DeleteSwarm.lua
-- Swarm deletion confirmation screen for shelfos-swarm
-- Handles complete swarm teardown with confirmation
-- Extracted from App.lua for maintainability

local Paths = mpm('shelfos-swarm/core/Paths')

local DeleteSwarm = {}

-- Delete entire swarm with confirmation
-- @param app App instance (needs authority for swarm info and deletion)
function DeleteSwarm.run(app)
    term.clear()
    term.setCursorPos(1, 1)

    local info = app.authority:getInfo()

    print("=====================================")
    print("         DELETE SWARM")
    print("=====================================")
    print("")
    print("WARNING: This will delete:")
    print("  - Swarm: " .. (info and info.name or "Unknown"))
    print("  - All " .. (info and info.zoneCount or 0) .. " registered zones")
    print("  - All credentials")
    print("")
    print("Zones will need to re-pair.")
    print("")
    print("[Y] Yes, delete everything")
    print("[N] No, keep swarm")

    while true do
        local _, key = os.pullEvent("key")

        if key == keys.y then
            -- Close network
            rednet.unhost("shelfos_swarm")

            -- Delete swarm
            app.authority:deleteSwarm()
            Paths.deleteAll()

            print("")
            print("[*] Swarm deleted")
            print("Rebooting...")
            sleep(2)
            os.reboot()

        elseif key == keys.n then
            return
        end
    end
end

return DeleteSwarm
