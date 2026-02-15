-- Mock Peripheral API
-- Simulates CC:Tweaked peripheral system for testing

local Peripheral = {}

-- Registry of attached peripherals
local attached = {}
local names_to_types = {}
local wrapper_to_name = {}  -- Maps wrapper tables to peripheral names

function Peripheral.reset()
    attached = {}
    names_to_types = {}
    wrapper_to_name = {}
end

function Peripheral.attach(name, type_name, peripheral_obj)
    attached[name] = peripheral_obj
    names_to_types[name] = type_name
end

function Peripheral.detach(name)
    attached[name] = nil
    names_to_types[name] = nil
end

-- CC:Tweaked peripheral API
function Peripheral.getNames()
    local names = {}
    for name in pairs(attached) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

function Peripheral.isPresent(name)
    return attached[name] ~= nil
end

function Peripheral.getType(name)
    return names_to_types[name]
end

function Peripheral.hasType(name, type_name)
    return names_to_types[name] == type_name
end

function Peripheral.getMethods(name)
    local p = attached[name]
    if not p then return nil end

    local seen = {}
    local methods = {}

    -- Scan instance fields
    for k, v in pairs(p) do
        if type(v) == "function" and not k:match("^_") then
            if not seen[k] then
                seen[k] = true
                table.insert(methods, k)
            end
        end
    end

    -- Also scan metatable __index (for class-based objects like MEBridge)
    -- CC:Tweaked's real getMethods also finds metatable methods
    local mt = getmetatable(p)
    if mt then
        local index = rawget(mt, "__index")
        if type(index) == "table" then
            for k, v in pairs(index) do
                if type(v) == "function" and not k:match("^_") then
                    if not seen[k] then
                        seen[k] = true
                        table.insert(methods, k)
                    end
                end
            end
        end
    end

    table.sort(methods)
    return methods
end

function Peripheral.getName(peripheral_obj)
    -- Check wrapper registry first
    if wrapper_to_name[peripheral_obj] then
        return wrapper_to_name[peripheral_obj]
    end

    -- Check raw attached peripherals
    for name, obj in pairs(attached) do
        if obj == peripheral_obj then
            return name
        end
    end

    return nil
end

function Peripheral.call(name, method, ...)
    local p = attached[name]
    if not p then
        error("No peripheral attached on side " .. name, 2)
    end
    if not p[method] then
        error("No such method " .. method, 2)
    end
    return p[method](p, ...)
end

function Peripheral.wrap(name)
    local p = attached[name]
    if not p then return nil end

    -- Create wrapper that auto-calls methods
    local wrapper = {}
    setmetatable(wrapper, {
        __index = function(_, method)
            if type(p[method]) == "function" then
                return function(...)
                    return p[method](p, ...)
                end
            end
            return p[method]
        end
    })

    -- Track wrapper for getName lookup
    wrapper_to_name[wrapper] = name

    return wrapper
end

-- CC:Tweaked peripheral.find() returns ALL matching wrapped peripherals as
-- multiple return values: wrapper1, wrapper2, ...
-- NOT (wrapper, name) - that was a bug in the original mock.
function Peripheral.find(type_name, filter_fn)
    local results = {}
    -- Sort names for deterministic order
    local sortedNames = {}
    for name in pairs(attached) do
        table.insert(sortedNames, name)
    end
    table.sort(sortedNames)

    for _, name in ipairs(sortedNames) do
        if names_to_types[name] == type_name then
            local obj = attached[name]
            if not filter_fn or filter_fn(name, obj) then
                table.insert(results, Peripheral.wrap(name))
            end
        end
    end

    if #results == 0 then return nil end
    return table.unpack(results)
end

-- Install into global _G.peripheral
function Peripheral.install()
    _G.peripheral = {
        getNames = Peripheral.getNames,
        isPresent = Peripheral.isPresent,
        getType = Peripheral.getType,
        hasType = Peripheral.hasType,
        getMethods = Peripheral.getMethods,
        getName = Peripheral.getName,
        call = Peripheral.call,
        wrap = Peripheral.wrap,
        find = Peripheral.find
    }
end

return Peripheral
