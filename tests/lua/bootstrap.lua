local M = {}

local function sorted_keys(tbl)
    local keys = {}
    for k in pairs(tbl) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta == tb then
            return tostring(a) < tostring(b)
        end
        return ta < tb
    end)
    return keys
end

local function serialize(value)
    local t = type(value)
    if t == "nil" then
        return "nil"
    elseif t == "number" or t == "boolean" then
        return tostring(value)
    elseif t == "string" then
        return string.format("%q", value)
    elseif t == "table" then
        local out = {"{"}
        local first = true
        for _, k in ipairs(sorted_keys(value)) do
            if not first then
                out[#out + 1] = ","
            end
            first = false
            out[#out + 1] = "["
            out[#out + 1] = serialize(k)
            out[#out + 1] = "]="
            out[#out + 1] = serialize(value[k])
        end
        out[#out + 1] = "}"
        return table.concat(out)
    end

    error("Unsupported value for serialize: " .. t)
end

local function unserialize(str)
    local chunk, err = load("return " .. str, "textutils.unserialize", "t", {})
    if not chunk then
        error(err)
    end
    return chunk()
end

local function install_cc_stubs()
    _G.textutils = _G.textutils or {}
    _G.textutils.serialize = _G.textutils.serialize or serialize
    _G.textutils.unserialize = _G.textutils.unserialize or unserialize

    _G.colors = _G.colors or {
        black = 1,
        white = 2,
        toBlit = function(c)
            local map = {
                [1] = "0",
                [2] = "f"
            }
            return map[c] or "0"
        end
    }

    local epoch = 1700000000000
    os.getComputerID = os.getComputerID or function()
        return 42
    end
    os.epoch = os.epoch or function()
        epoch = epoch + 11
        return epoch
    end
end

function M.setup_package_paths(root)
    package.path = table.concat({
        root .. "/?.lua",
        root .. "/?/init.lua",
        root .. "/mpm/?.lua",
        root .. "/mpm/?/init.lua",
        root .. "/mpm-packages/?.lua",
        root .. "/mpm-packages/?/init.lua",
        package.path,
    }, ";")
end

function M.bootstrap(root)
    install_cc_stubs()
    M.setup_package_paths(root)
end

return M
