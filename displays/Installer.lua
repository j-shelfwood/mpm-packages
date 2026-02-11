-- Installer.lua
-- Setup wizard for displays package
-- Refactored to use shared view management

local Config = mpm('displays/Config')
local ViewManager = mpm('views/Manager')

local Installer = {}

-- Show monitor identifiers on all connected monitors
local function showMonitorIdentifiers()
    local names = peripheral.getNames()

    for _, name in ipairs(names) do
        if peripheral.hasType(name, "monitor") then
            local monitor = peripheral.wrap(name)
            if monitor then
                monitor.setTextScale(1)
                monitor.setBackgroundColor(colors.blue)
                monitor.clear()
                monitor.setTextColor(colors.white)

                local width, height = monitor.getSize()
                local centerY = math.floor(height / 2)

                -- Display name
                local displayName = name
                if #displayName > width - 2 then
                    displayName = displayName:sub(1, width - 5) .. "..."
                end

                local x = math.floor((width - #displayName) / 2) + 1
                monitor.setCursorPos(x, centerY)
                monitor.write(displayName)

                monitor.setBackgroundColor(colors.black)
            end
        end
    end
end

-- Clear all monitor identifiers
local function clearMonitorIdentifiers()
    local names = peripheral.getNames()

    for _, name in ipairs(names) do
        if peripheral.hasType(name, "monitor") then
            local monitor = peripheral.wrap(name)
            if monitor then
                monitor.setBackgroundColor(colors.black)
                monitor.clear()
            end
        end
    end
end

-- Get list of unconfigured monitors
local function getUnconfiguredMonitors(existingConfig)
    local configured = {}
    for _, entry in ipairs(existingConfig) do
        configured[entry.monitor] = true
    end

    local unconfigured = {}
    local names = peripheral.getNames()

    for _, name in ipairs(names) do
        if peripheral.hasType(name, "monitor") and not configured[name] then
            table.insert(unconfigured, name)
        end
    end

    return unconfigured
end

-- Let user select a view
local function selectView(views)
    print("")
    print("Available views:")

    for i, viewName in ipairs(views) do
        print("  " .. i .. ". " .. viewName)
    end

    print("  0. Skip this monitor")
    print("")
    write("Select (0-" .. #views .. "): ")

    local input = read()
    local choice = tonumber(input)

    if not choice or choice < 0 or choice > #views then
        return nil
    end

    if choice == 0 then
        return nil
    end

    return views[choice]
end

-- Run the installer
function Installer.run()
    term.clear()
    term.setCursorPos(1, 1)

    print("================================")
    print("  Displays Setup Wizard")
    print("================================")
    print("")

    -- Load existing config
    local config = Config.load()
    print("[*] Existing displays: " .. #config)

    -- Find unconfigured monitors
    local unconfigured = getUnconfiguredMonitors(config)

    if #unconfigured == 0 then
        print("[*] All monitors already configured")
        print("")
        print("To reconfigure, delete displays.config")
        return
    end

    print("[*] New monitors found: " .. #unconfigured)
    print("")

    -- Show identifiers
    print("Monitor names are now displayed on each screen.")
    showMonitorIdentifiers()

    -- Get mountable views
    local views = ViewManager.getMountableViews()

    if #views == 0 then
        print("")
        print("[!] No views available")
        print("    Check peripheral connections")
        clearMonitorIdentifiers()
        return
    end

    -- Configure each monitor
    local newDisplays = {}

    for _, monitorName in ipairs(unconfigured) do
        print("")
        print("=== " .. monitorName .. " ===")

        local viewName = selectView(views)

        if viewName then
            -- Get view config if view has configure()
            local viewConfig = {}
            local View = ViewManager.load(viewName)

            if View and View.configure then
                print("")
                print("Configure " .. viewName .. ":")
                local ok, cfg = pcall(View.configure)
                if ok and cfg then
                    viewConfig = cfg
                end
            end

            table.insert(newDisplays, {
                monitor = monitorName,
                view = viewName,
                config = viewConfig
            })

            print("[+] " .. monitorName .. " -> " .. viewName)
        else
            print("[-] " .. monitorName .. " skipped")
        end
    end

    -- Clear identifiers
    clearMonitorIdentifiers()

    -- Merge with existing config
    for _, display in ipairs(newDisplays) do
        table.insert(config, display)
    end

    -- Save
    if #newDisplays > 0 then
        Config.save(config)
        print("")
        print("[*] Configuration saved to " .. Config.getPath())
    end

    -- Offer to create startup
    print("")
    print("Create startup.lua to auto-run displays? (y/n)")
    write("> ")

    if read():lower() == "y" then
        local file = fs.open("startup.lua", "w")
        file.write("shell.run('mpm run displays')")
        file.close()
        print("[*] startup.lua created")
    end

    print("")
    print("=== Setup Complete ===")
    print("")
    print("Run displays with: mpm run displays")
end

return Installer
