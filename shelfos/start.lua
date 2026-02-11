-- ShelfOS - Base Information System
-- Entry point: mpm run shelfos

local args = {...}
local command = args[1]

if command == "setup" then
    -- Manual setup wizard (reconfiguration)
    local setup = mpm('shelfos/tools/setup')
    setup.run()

elseif command == "link" then
    -- Link to existing network
    local code = args[2]
    local link = mpm('shelfos/tools/link')
    link.run(code)

elseif command == "status" then
    -- Show system status
    local Config = mpm('shelfos/core/Config')
    local config = Config.load()

    if not config then
        print("[ShelfOS] Not configured")
        return
    end

    print("[ShelfOS] Status")
    print("  Zone: " .. (config.zone.name or "Unknown"))
    print("  Zone ID: " .. (config.zone.id or "N/A"))
    print("  Monitors: " .. #(config.monitors or {}))
    print("  Network: " .. (config.network.enabled and "enabled" or "disabled"))

    for _, m in ipairs(config.monitors or {}) do
        print("    - " .. m.peripheral .. " -> " .. m.view)
    end

elseif command == "reset" then
    -- Reset configuration
    local Config = mpm('shelfos/core/Config')
    if fs.exists(Config.getPath()) then
        fs.delete(Config.getPath())
        print("[ShelfOS] Configuration deleted")
        print("[ShelfOS] Run 'mpm run shelfos' to auto-configure")
    else
        print("[ShelfOS] No configuration to delete")
    end

else
    -- Normal startup with auto-discovery
    local Kernel = mpm('shelfos/core/Kernel')
    local kernel = Kernel.new()

    if kernel:boot() then
        kernel:run()
    end
end
