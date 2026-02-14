-- KernelPairing.lua
-- Pocket pairing flow for Kernel
-- Handles display-code security model (code shown on screen, never broadcast)
-- Extracted from Kernel.lua for maintainability

local EventUtils = mpm('utils/EventUtils')
local PairingScreen = mpm('shelfos/ui/PairingScreen')
local Config = mpm('shelfos/core/Config')

local KernelPairing = {}

-- Accept pairing from a pocket computer
-- This is how zones join the swarm - pocket delivers the secret
-- SECURITY: A code is displayed on screen (never broadcast)
-- The pocket user must enter this code to complete pairing
-- @param kernel Kernel instance
-- @return success boolean
function KernelPairing.acceptFromPocket(kernel)
    local Pairing = mpm('net/Pairing')

    local modem = peripheral.find("modem")
    if not modem then
        print("")
        print("[!] No modem found")
        EventUtils.sleep(2)
        return false
    end

    local modemType = modem.isWireless() and "wireless" or "wired"
    local computerLabel = os.getComputerLabel() or ("Computer #" .. os.getComputerID())

    -- Find all connected monitors
    local monitorNames = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name, "monitor") then
            table.insert(monitorNames, name)
        end
    end

    -- Close existing channel temporarily
    if kernel.channel then
        rednet.unhost("shelfos")
        kernel.channel:close()
        kernel.channel = nil
    end

    -- PAUSE all monitor rendering so pairing code stays visible
    for _, monitor in ipairs(kernel.monitors) do
        monitor:setPairingMode(true)
    end

    -- Use Pairing module with callbacks
    local displayCode = nil

    local callbacks = {
        onDisplayCode = function(code)
            displayCode = code

            -- Display code on ALL monitors (large as possible)
            for _, name in ipairs(monitorNames) do
                local mon = peripheral.wrap(name)
                if mon then
                    PairingScreen.drawCode(mon, code, computerLabel)
                end
            end

            -- Also draw on terminal
            print("")
            print("=====================================")
            print("   Waiting for Pocket Pairing")
            print("=====================================")
            print("")
            print("  Computer: " .. computerLabel)
            print("  Modem: " .. modemType)
            print("")
            print("  +-----------------------+")
            print("  |  PAIRING CODE:        |")
            print("  |                       |")
            print("  |      " .. code .. "      |")
            print("  |                       |")
            print("  +-----------------------+")
            print("")
            if #monitorNames > 0 then
                print("Code shown on " .. #monitorNames .. " monitor(s)")
            end
            print("")
            print("On your pocket computer:")
            print("  1. Run: mpm run shelfos-swarm")
            print("  2. Press [A] -> Add Zone")
            print("  3. Select this zone, enter code")
            print("")
            print("Press [Q] to cancel")
        end,
        onStatus = function(msg)
            -- Update status line (redraw bottom area)
            local _, h = term.getSize()
            term.setCursorPos(1, h - 1)
            term.clearLine()
            term.write("[*] " .. msg)
        end,
        onSuccess = function(secret, zoneId)
            -- RESUME monitor rendering
            for _, monitor in ipairs(kernel.monitors) do
                monitor:setPairingMode(false)
            end

            -- Clear monitor displays
            PairingScreen.clearAll(monitorNames)

            print("")
            print("")
            print("[*] Pairing successful!")
            print("[*] Initializing network...")
        end,
        onCancel = function(reason)
            -- RESUME monitor rendering
            for _, monitor in ipairs(kernel.monitors) do
                monitor:setPairingMode(false)
            end

            -- Clear monitor displays
            PairingScreen.clearAll(monitorNames)

            print("")
            print("")
            print("[*] " .. (reason or "Cancelled"))
        end
    }

    local success, secret, zoneId = Pairing.acceptFromPocket(callbacks)

    if success then
        -- Save credentials
        Config.setNetworkSecret(kernel.config, secret)
        if zoneId then
            kernel.config.zone = kernel.config.zone or {}
            kernel.config.zone.id = zoneId
        end
        Config.save(kernel.config)

        -- Initialize network immediately (no restart required)
        kernel:initializeNetwork()
        print("[*] Connected to swarm!")
    end

    EventUtils.sleep(2)
    return success
end

return KernelPairing
