-- MenuStatus.lua
-- Status dialog rendering for Menu
-- Shows computer info, monitors, swarm status, peripherals
-- Extracted from Menu.lua for maintainability

local Controller = mpm('ui/Controller')

local MenuStatus = {}

-- Build status lines for display
-- @param config ShelfOS configuration
-- @return Array of lines to display
function MenuStatus.buildLines(config)
    local lines = {
        "",
        "Computer: " .. (config.computer.name or "Unknown"),
        "Computer ID: " .. (config.computer.id or "N/A"),
        ""
    }

    -- Monitor list
    local monitors = config.monitors or {}
    table.insert(lines, "Monitors (" .. #monitors .. "):")

    for _, m in ipairs(monitors) do
        table.insert(lines, "  " .. m.peripheral .. " -> " .. m.view)
    end

    table.insert(lines, "")

    -- Network/Swarm status (check if secret exists, not just enabled flag)
    local isInSwarm = config.network and config.network.secret ~= nil
    if isInSwarm then
        -- Check for swarm peers using native rednet.lookup
        local peerCount = 0
        local peerIds = {}
        local modemOpen = false

        -- Check if rednet is available (modem must be open)
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.hasType(name, "modem") then
                if rednet.isOpen(name) then
                    modemOpen = true
                    break
                end
            end
        end

        if modemOpen then
            peerIds = {rednet.lookup("shelfos")}
            peerCount = #peerIds
        end

        -- Swarm status line
        if peerCount > 0 then
            local peerWord = peerCount == 1 and "peer" or "peers"
            table.insert(lines, "Swarm of " .. peerCount .. " " .. peerWord .. " online")
            table.insert(lines, "  IDs: " .. table.concat(peerIds, ", "))
        else
            table.insert(lines, "Swarm: No peers found")
            table.insert(lines, "  (other computers may be offline)")
        end

        table.insert(lines, "")
        table.insert(lines, "Use pocket computer to add computers")
    else
        table.insert(lines, "Network: Standalone (not in swarm)")
        table.insert(lines, "  Press [L] to pair with pocket")
    end

    -- Local shared peripherals (shareable types)
    if isInSwarm then
        local shareableTypes = {
            me_bridge = true, rsBridge = true, energyStorage = true,
            energy_storage = true, inventory = true, chest = true,
            fluid_storage = true, environment_detector = true,
            player_detector = true, colony_integrator = true, chat_box = true,
            energy_detector = true, energyDetector = true
        }
        local shared = {}
        for _, name in ipairs(peripheral.getNames()) do
            local pType = peripheral.getType(name)
            if shareableTypes[pType] then
                table.insert(shared, {name = name, type = pType})
            end
        end

        table.insert(lines, "")
        table.insert(lines, "Sharing (" .. #shared .. " local):")
        if #shared == 0 then
            table.insert(lines, "  (no shareable peripherals)")
        else
            for _, p in ipairs(shared) do
                table.insert(lines, "  " .. p.name .. " [" .. p.type .. "]")
            end
        end
    end

    -- Remote peripherals (if available)
    local ok, RemotePeripheral = pcall(mpm, 'net/RemotePeripheral')
    if ok and RemotePeripheral and RemotePeripheral.hasClient() then
        local client = RemotePeripheral.getClient()
        local remotePeriphs = {}

        -- Get remote peripherals with host info
        if client and client.remotePeripherals then
            for name, info in pairs(client.remotePeripherals) do
                local hostComputer = client.hostComputers[info.hostId]
                local hostName = hostComputer and hostComputer.computerName or ("Computer #" .. info.hostId)
                table.insert(remotePeriphs, {
                    name = info.displayName or name,
                    type = info.type,
                    host = hostName
                })
            end
        end

        table.insert(lines, "")
        table.insert(lines, "Remote (" .. #remotePeriphs .. " available):")
        if #remotePeriphs == 0 then
            table.insert(lines, "  (none discovered yet)")
        else
            for _, p in ipairs(remotePeriphs) do
                table.insert(lines, "  " .. p.name .. " [" .. p.type .. "]")
                table.insert(lines, "    from: " .. p.host)
            end
        end
    elseif isInSwarm then
        table.insert(lines, "")
        table.insert(lines, "Remote: (client not initialized)")
    end

    return lines
end

-- Show status dialog
-- @param config ShelfOS configuration
-- @param target Term-like object (default: term.current())
function MenuStatus.show(config, target)
    target = target or term.current()
    local lines = MenuStatus.buildLines(config)
    Controller.showInfo(target, "ShelfOS Status", lines)
end

return MenuStatus
