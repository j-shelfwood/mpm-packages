-- KernelPairing.lua
-- Pocket pairing flow for Kernel
-- Handles display-code security model (code shown on screen, never broadcast)
-- Extracted from Kernel.lua for maintainability

local PairingScreen = mpm('shelfos/ui/PairingScreen')
local Config = mpm('shelfos/core/Config')
local ModemUtils = mpm('utils/ModemUtils')
local Terminal = mpm('shelfos/core/Terminal')

local KernelPairing = {}

local function waitSeconds(seconds)
    local timer = os.startTimer(seconds)
    while true do
        local event, id = os.pullEvent()
        if event == "timer" and id == timer then
            return
        end
    end
end

-- Accept pairing from a pocket computer
-- This is how computers join the swarm - pocket delivers the secret
-- SECURITY: A code is displayed on screen (never broadcast)
-- The pocket user must enter this code to complete pairing
-- @param kernel Kernel instance
-- @return success boolean
function KernelPairing.acceptFromPocket(kernel)
    local Pairing = mpm('net/Pairing')

    -- Pre-validate modem exists (Pairing.acceptFromPocket will open it with ModemUtils.open)
    local modem, modemName, modemType = ModemUtils.find(true)
    if not modem then
        print("")
        print("[!] No modem found")
        waitSeconds(2)
        return false
    end
    local computerLabel = os.getComputerLabel() or ("Computer #" .. os.getComputerID())
    local native = term.native()

    -- Find all connected monitors
    local monitorNames = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name, "monitor") then
            table.insert(monitorNames, name)
        end
    end

    -- Close existing channel temporarily
    if kernel.channel then
        local KernelNetwork = mpm('shelfos/core/KernelNetwork')
        KernelNetwork.close(kernel.channel)
        kernel.channel = nil
    end

    -- PAUSE all monitor rendering so pairing code stays visible
    kernel.pairingActive = true
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

            -- Always draw pairing code on native terminal.
            -- This is required for terminal-only (0 monitor) nodes.
            term.redirect(native)
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
            term.clear()
            term.setCursorPos(1, 1)
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
            else
                print("No monitors attached; pairing code shown in this terminal.")
            end
            print("")
            print("On your pocket computer:")
            print("  1. Run: mpm run shelfos-swarm")
            print("  2. Press [A] -> Add Computer")
            print("  3. Select this computer, enter code")
            print("")
            print("Press [Q] to cancel")
        end,
        onStatus = function(msg)
            -- Update status line (redraw bottom area)
            term.redirect(native)
            local _, h = term.getSize()
            term.setCursorPos(1, h - 1)
            term.clearLine()
            term.write("[*] " .. msg)
        end,
        onSuccess = function(secret, computerId)
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

    local success, secret, computerId = Pairing.acceptFromPocket(callbacks)

    if success then
        -- Save credentials
        Config.setNetworkSecret(kernel.config, secret)
        if computerId then
            kernel.config.computer = kernel.config.computer or {}
            kernel.config.computer.id = computerId
        end
        Config.save(kernel.config)

        -- Initialize network immediately (no restart required)
        kernel:initializeNetwork()
        print("[*] Connected to swarm!")
    end

    for _, monitor in ipairs(kernel.monitors) do
        monitor:setPairingMode(false)
    end
    PairingScreen.clearAll(monitorNames)
    kernel.pairingActive = false
    Terminal.redirectToLog()
    if kernel.dashboard then
        kernel.dashboard:requestRedraw()
    end

    waitSeconds(2)
    return success
end

return KernelPairing
