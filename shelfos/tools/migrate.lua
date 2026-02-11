-- migrate.lua
-- Migrate from legacy displays package to ShelfOS

local Config = mpm('shelfos/core/Config')
local Zone = mpm('shelfos/core/Zone')

local migrate = {}

-- Path to legacy config
local LEGACY_CONFIG_PATH = "/displays.config"

-- Run migration
function migrate.run()
    term.clear()
    term.setCursorPos(1, 1)

    print("================================")
    print("  ShelfOS Migration Tool")
    print("================================")
    print("")

    -- Check for existing ShelfOS config
    if Config.exists() then
        print("[!] ShelfOS configuration already exists.")
        print("    Delete /shelfos.config to migrate again.")
        return
    end

    -- Check for legacy config
    if not fs.exists(LEGACY_CONFIG_PATH) then
        print("[!] No legacy displays.config found.")
        print("    Run 'mpm run shelfos setup' for fresh setup.")
        return
    end

    -- Load legacy config
    print("Loading legacy configuration...")

    local file = fs.open(LEGACY_CONFIG_PATH, "r")
    if not file then
        print("[!] Failed to read displays.config")
        return
    end

    local content = file.readAll()
    file.close()

    local ok, legacyConfig = pcall(textutils.unserialize, content)
    if not ok or not legacyConfig then
        print("[!] Failed to parse displays.config")
        return
    end

    print("[*] Found " .. #legacyConfig .. " display(s)")
    print("")

    -- Create new config
    local zoneId = Zone.generateId()
    local zoneName = "Migrated Zone"

    print("Zone name (default: Migrated Zone):")
    write("> ")
    local inputName = read()
    if inputName ~= "" then
        zoneName = inputName
    end

    local config = Config.create(zoneId, zoneName)

    -- Migrate monitors
    print("")
    print("Migrating displays...")

    for _, display in ipairs(legacyConfig) do
        local monitorName = display.monitor
        local viewName = display.view

        if monitorName and viewName then
            print("  [+] " .. monitorName .. " -> " .. viewName)

            Config.addMonitor(config, monitorName, viewName, display.viewConfig or {})
        else
            print("  [-] Invalid display entry, skipping")
        end
    end

    -- Ask about networking
    print("")
    print("Enable networking? (requires modem)")
    write("(y/n): ")

    if read():lower() == "y" then
        local Crypto = mpm('net/Crypto')

        print("")
        print("Enter shared secret (min 16 chars):")
        write("> ")
        local secret = read()

        if #secret >= 16 then
            Config.setNetworkSecret(config, secret)
            print("[*] Networking enabled")
        else
            print("[!] Secret too short, networking disabled")
        end
    end

    -- Save new config
    print("")
    print("Saving ShelfOS configuration...")

    local saved = Config.save(config)

    if saved then
        print("[*] Configuration saved!")
        print("")
        print("=== Migration Complete ===")
        print("")
        print("Your legacy displays.config has been")
        print("converted to ShelfOS format.")
        print("")
        print("Legacy config preserved at:")
        print("  " .. LEGACY_CONFIG_PATH)
        print("")
        print("Start ShelfOS with: mpm run shelfos")
        print("")

        -- Offer to rename legacy config
        print("Rename legacy config to .bak? (y/n)")
        write("> ")
        if read():lower() == "y" then
            fs.move(LEGACY_CONFIG_PATH, LEGACY_CONFIG_PATH .. ".bak")
            print("[*] Renamed to displays.config.bak")
        end
    else
        print("[!] Failed to save configuration")
    end
end

return migrate
