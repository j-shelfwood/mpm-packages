-- ViewZones.lua
-- Zone registry display for shelfos-swarm
-- Shows all registered zones in the swarm
-- Extracted from App.lua for maintainability

local ViewZones = {}

-- Display all zones in the swarm
-- @param app App instance (needs authority for zone registry)
function ViewZones.run(app)
    term.clear()
    term.setCursorPos(1, 1)

    print("=====================================")
    print("           Zone Registry")
    print("=====================================")
    print("")

    local zones = app.authority:getZones()

    if #zones == 0 then
        print("No zones registered.")
        print("")
        print("Use [A] Add Zone to pair computers.")
    else
        for i, zone in ipairs(zones) do
            local status = zone.status == "active" and "+" or "x"
            print("[" .. status .. "] " .. zone.label)
            print("    ID: " .. zone.id)
            print("    Fingerprint: " .. zone.fingerprint)
            print("")
        end
    end

    print("-------------------")
    print("[B] Back")

    while true do
        local _, key = os.pullEvent("key")
        if key == keys.b then
            return
        end
    end
end

return ViewZones
