-- link.lua
-- Network status tool for ShelfOS
-- Pairing is now done via pocket computer only

local Config = mpm('shelfos/core/Config')
local ModemUtils = mpm('utils/ModemUtils')

local link = {}

-- Show current link status
local function showStatus()
    local config = Config.load()

    print("")
    print("[ShelfOS] Network Status")
    print("")

    if not config then
        print("  Not configured. Run 'mpm run shelfos' first.")
        return
    end

    print("  Computer: " .. (config.computer.name or "Unknown"))
    print("  Computer ID: " .. (config.computer.id or "Unknown"))
    print("")

    if Config.isInSwarm(config) then
        print("  Swarm: Connected")

        -- Check for modem (prefer wireless/ender for swarm communication)
        local modem, modemName, modemType = ModemUtils.find(true)
        if modem then
            -- ModemUtils returns "ender" or "wired"
            local modemLabel = modemType == "ender" and "Ender" or "Wired"
            print("  Modem: " .. modemLabel)

            -- Try to get peer count
            if not rednet.isOpen(modemName) then
                rednet.open(modemName)
            end
            local peerIds = {rednet.lookup("shelfos")}
            if #peerIds > 0 then
                print("  Peers: " .. #peerIds .. " online")
            else
                print("  Peers: None found")
            end
        else
            print("  Modem: Not found")
        end

        print("")
        print("  To add more computers:")
        print("    Use pocket computer -> Add Computer")
    else
        print("  Swarm: Not connected")
        print("")
        print("  To join a swarm:")
        print("    1. Run ShelfOS: mpm run shelfos")
        print("    2. Press L -> Accept from pocket")
        print("    3. Pair from pocket computer")
    end
end

-- Main entry point
function link.run(arg)
    showStatus()
end

return link
