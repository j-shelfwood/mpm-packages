-- ai/Bridge.lua
-- MCP Bridge - connects this CC computer to the mpm-mcp-server
-- Allows AI agents (Claude, etc.) to execute Lua, read/write files,
-- and call peripherals on this computer.
--
-- Usage: mpm bridge <host-or-url> [port]
--   mpm bridge 192.168.1.x              (LAN, default port 5757)
--   mpm bridge 192.168.1.x 5757
--   mpm bridge wss://xyz.trycloudflare.com

local args = {...}
local target = args[1]
local port = tonumber(args[2]) or 5757

if not target then
    print("Usage: mpm bridge <host-or-url> [port]")
    print("  mpm bridge 192.168.1.x")
    print("  mpm bridge wss://xyz.trycloudflare.com")
    return
end

-- Accept full ws:// or wss:// URLs, or build from host:port
local url
if target:match("^wss?://") then
    url = target
else
    url = "ws://" .. target .. ":" .. port
end

print("[mpm-bridge] Connecting to " .. url .. "...")

local ws, err = http.websocket(url)
if not ws then
    printError("[mpm-bridge] Connection failed: " .. tostring(err))
    return
end

print("[mpm-bridge] Connected. Registering computer...")

-- Register this computer with the server
ws.send(textutils.serialiseJSON({
    type = "register",
    id = os.getComputerID(),
    label = os.getComputerLabel() or ("Computer #" .. os.getComputerID()),
}))

-- Wait for registration confirmation
local raw = ws.receive(5)
if not raw then
    printError("[mpm-bridge] Registration timeout.")
    ws.close()
    return
end

local reg = textutils.unserialiseJSON(raw)
if not reg or not reg.ok then
    printError("[mpm-bridge] Registration rejected.")
    ws.close()
    return
end

print("[mpm-bridge] Registered as: " .. (os.getComputerLabel() or "Computer #" .. os.getComputerID()))
print("[mpm-bridge] Ready. Press Ctrl+T to disconnect.")

-- ── Command handlers ──────────────────────────────────────────────────────

local Peripherals = mpm('utils/Peripherals')
local okRemote, RemotePeripheral = pcall(mpm, 'net/RemotePeripheral')
if okRemote and RemotePeripheral then
    _G._native_peripheral = _G._native_peripheral or peripheral
    _G.peripheral = RemotePeripheral
end

local function handleListFiles(payload)
    local path = payload.path or "/"
    if not fs.exists(path) then
        return false, "Path does not exist: " .. path
    end

    local entries = {}
    for _, name in ipairs(fs.list(path)) do
        local full = fs.combine(path, name)
        table.insert(entries, {
            name = name,
            isDir = fs.isDir(full),
            size = fs.isDir(full) and 0 or fs.getSize(full),
        })
    end
    return true, entries
end

local function handleReadFile(payload)
    local path = payload.path
    if not path then return false, "payload.path required" end
    if not fs.exists(path) then return false, "File not found: " .. path end
    if fs.isDir(path) then return false, "Path is a directory: " .. path end

    local f, ferr = fs.open(path, "r")
    if not f then return false, "Cannot open file: " .. tostring(ferr) end
    local content = f.readAll()
    f.close()
    return true, content
end

local function handleWriteFile(payload)
    local path = payload.path
    local content = payload.content
    if not path then return false, "payload.path required" end
    if content == nil then return false, "payload.content required" end

    local f, ferr = fs.open(path, "w")
    if not f then return false, "Cannot open file for writing: " .. tostring(ferr) end
    f.write(tostring(content))
    f.close()
    return true, nil
end

local function handleListPeripherals(_payload)
    local names = Peripherals.getNames()
    local result = {}
    for _, name in ipairs(names) do
        table.insert(result, {
            name = name,
            type = Peripherals.getType(name),
        })
    end
    return true, result
end

local function handleCallPeripheral(payload)
    local pname = payload.peripheral
    local method = payload.method
    local pargs = payload.args or {}

    if not pname then return false, "payload.peripheral required" end
    if not method then return false, "payload.method required" end
    if not Peripherals.isPresent(pname) then
        return false, "Peripheral not present: " .. pname
    end

    local ok, results = pcall(function()
        return table.pack(Peripherals.call(pname, method, table.unpack(pargs)))
    end)

    if not ok then
        return false, tostring(results)
    end

    local out = {}
    for i = 1, results.n do out[i] = results[i] end
    return true, (#out == 0 and textutils.empty_json_array or out)
end

local handlers = {
    list_files      = handleListFiles,
    read_file       = handleReadFile,
    write_file      = handleWriteFile,
    list_peripherals = handleListPeripherals,
    call_peripheral = handleCallPeripheral,
}

-- ── Main receive loop ─────────────────────────────────────────────────────

local running = true

parallel.waitForAny(
    -- Message dispatch loop
    function()
        while running do
            local msg = ws.receive()
            if not msg then
                print("[mpm-bridge] Connection closed by server.")
                running = false
                return
            end

            local cmd = textutils.unserialiseJSON(msg)
            if not cmd or not cmd.type or not cmd.requestId then
                -- Ignore malformed messages
            else
                local handler = handlers[cmd.type]
                local response

                if not handler then
                    response = {
                        type = "result",
                        requestId = cmd.requestId,
                        ok = false,
                        error = "Unknown command type: " .. tostring(cmd.type),
                    }
                else
                    local ok, data = handler(cmd.payload or {})
                    response = {
                        type = "result",
                        requestId = cmd.requestId,
                        ok = ok,
                        data = ok and data or nil,
                        error = (not ok) and tostring(data) or nil,
                    }
                end

                ws.send(textutils.serialiseJSON(response))
            end
        end
    end,

    -- Keyboard: Ctrl+T to quit
    function()
        while running do
            local event, key = os.pullEvent("key")
            if event == "key" and key == keys.t and (keys.isHeld and keys.isHeld(keys.leftCtrl) or false) then
                running = false
                return
            end
        end
    end,

    -- Terminate event
    function()
        os.pullEvent("terminate")
        running = false
    end
)

ws.close()
print("[mpm-bridge] Disconnected.")
