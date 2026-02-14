-- Mock Framework for ShelfOS Testing
-- Provides realistic CC:Tweaked peripheral simulation

local Mocks = {}

-- Load individual mock modules
local root = ...
if root then
    root = root:gsub("%.init$", "")
else
    root = "tests.lua.mocks"
end

local Peripheral = require(root .. ".peripheral")
local Rednet = require(root .. ".rednet")
local Modem = require(root .. ".modem")
local MEBridge = require(root .. ".me_bridge")
local Monitor = require(root .. ".monitor")
local Fs = require(root .. ".fs")

Mocks.Peripheral = Peripheral
Mocks.Rednet = Rednet
Mocks.Modem = Modem
Mocks.MEBridge = MEBridge
Mocks.Monitor = Monitor
Mocks.Fs = Fs

-- Quick setup for common test scenarios
function Mocks.reset()
    Peripheral.reset()
    Rednet.reset()
    Fs.reset()
end

-- Install all mocks into global namespace
function Mocks.install()
    Peripheral.install()
    Rednet.install()
    Fs.install()
end

-- Setup pocket computer with ender modem
function Mocks.setupPocket(config)
    config = config or {}
    Mocks.reset()
    Mocks.install()

    -- Stub pocket API
    _G.pocket = {
        equipBack = function() return true end,
        unequipBack = function() return true end
    }

    -- Attach ender modem on back
    local modem = Modem.new({
        name = "back",
        wireless = true  -- ender modems report as wireless
    })
    Peripheral.attach("back", "modem", modem)

    -- Set computer ID
    local id = config.id or 1
    _G.os.getComputerID = function() return id end
    _G.os.getComputerLabel = function() return config.label or "Pocket #" .. id end

    return {
        modem = modem,
        id = id
    }
end

-- Setup computer with modem and monitors
function Mocks.setupComputer(config)
    config = config or {}
    Mocks.reset()
    Mocks.install()

    -- No pocket API on computers
    _G.pocket = nil

    -- Attach modem
    local modemName = config.modemName or "top"
    local modem = Modem.new({
        name = modemName,
        wireless = config.wireless ~= false
    })
    Peripheral.attach(modemName, "modem", modem)

    -- Attach monitor(s)
    local monitors = {}
    local monitorCount = config.monitors or 1
    for i = 1, monitorCount do
        local name = "monitor_" .. (i - 1)
        local mon = Monitor.new(config.monitorConfig)
        Peripheral.attach(name, "monitor", mon)
        monitors[name] = mon
    end

    -- Attach ME Bridge if requested
    local meBridge = nil
    if config.meBridge ~= false then
        meBridge = MEBridge.new(config.meBridgeConfig)
        Peripheral.attach("me_bridge_0", "me_bridge", meBridge)
    end

    -- Set computer ID
    local id = config.id or 10
    _G.os.getComputerID = function() return id end
    _G.os.getComputerLabel = function() return config.label or "Computer #" .. id end

    return {
        modem = modem,
        modemName = modemName,
        monitors = monitors,
        meBridge = meBridge,
        id = id
    }
end

-- Backward compatibility alias
Mocks.setupZone = Mocks.setupComputer

-- Setup headless computer (no monitors, just peripherals)
function Mocks.setupHeadless(config)
    config = config or {}
    config.monitors = 0
    return Mocks.setupComputer(config)
end

-- Simulate pairing message exchange between pocket and computer
function Mocks.simulatePairing(pocket, computer, displayCode)
    local Protocol = require("mpm-packages.net.Protocol")
    local Crypto = require("mpm-packages.net.Crypto")

    -- Computer broadcasts PAIR_READY
    local pairReady = Protocol.createPairReady(nil, computer.label or "Computer", computer.id)

    -- Pocket receives PAIR_READY
    Rednet.queueMessage(computer.id, pairReady, "shelfos_pair")

    -- Pocket sends signed PAIR_DELIVER
    local creds = {
        swarmSecret = "test_swarm_secret_12345",
        computerId = "computer_" .. computer.id,
        swarmId = "swarm_pocket_" .. pocket.id,
        swarmFingerprint = "TEST-SWRM-FP01"
    }
    local deliver = Protocol.createPairDeliver(creds.swarmSecret, creds.computerId)
    deliver.data.credentials = creds

    local signedDeliver = Crypto.wrapWith(deliver, displayCode)

    -- Computer receives signed PAIR_DELIVER
    Rednet.queueMessage(pocket.id, signedDeliver, "shelfos_pair")

    return creds
end

-- Assert helpers for tests
function Mocks.assertBroadcast(protocol, msgType)
    local log = Rednet.getBroadcastLog()
    for _, entry in ipairs(log) do
        if entry.protocol == protocol then
            if not msgType or (entry.message and entry.message.type == msgType) then
                return entry
            end
        end
    end
    error("Expected broadcast with protocol=" .. protocol ..
          (msgType and " type=" .. msgType or "") .. " not found")
end

function Mocks.assertSend(recipient, protocol, msgType)
    local log = Rednet.getSendLog()
    for _, entry in ipairs(log) do
        if entry.recipient == recipient and entry.protocol == protocol then
            if not msgType or (entry.message and entry.message.type == msgType) then
                return entry
            end
        end
    end
    error("Expected send to " .. recipient .. " with protocol=" .. protocol ..
          (msgType and " type=" .. msgType or "") .. " not found")
end

return Mocks
