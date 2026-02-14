-- Mock Filesystem API
-- Simulates CC:Tweaked fs module for testing
-- Reference: https://tweaked.cc/module/fs.html

local Fs = {}

-- Virtual filesystem storage
local files = {}
local directories = {}

function Fs.reset()
    files = {}
    directories = {
        ["/"] = true
    }
end

-- Initialize with default directories
Fs.reset()

-- Check if path exists (file or directory)
function Fs.exists(path)
    path = Fs.normalize(path)
    return files[path] ~= nil or directories[path] ~= nil
end

-- Check if path is a directory
function Fs.isDir(path)
    path = Fs.normalize(path)
    return directories[path] == true
end

-- Get file/directory size
function Fs.getSize(path)
    path = Fs.normalize(path)
    if files[path] then
        return #files[path]
    end
    return 0
end

-- Normalize path (remove trailing slashes, handle ..)
function Fs.normalize(path)
    if not path then return "/" end
    -- Ensure leading slash
    if path:sub(1, 1) ~= "/" then
        path = "/" .. path
    end
    -- Remove trailing slash (except for root)
    if #path > 1 and path:sub(-1) == "/" then
        path = path:sub(1, -2)
    end
    return path
end

-- Combine path segments
function Fs.combine(base, child)
    base = Fs.normalize(base)
    if base == "/" then
        return "/" .. child
    end
    return base .. "/" .. child
end

-- Get parent directory
function Fs.getDir(path)
    path = Fs.normalize(path)
    local parent = path:match("^(.+)/[^/]+$")
    return parent or "/"
end

-- Get filename from path
function Fs.getName(path)
    path = Fs.normalize(path)
    return path:match("[^/]+$") or ""
end

-- Create directory
function Fs.makeDir(path)
    path = Fs.normalize(path)
    directories[path] = true
end

-- Delete file or directory
function Fs.delete(path)
    path = Fs.normalize(path)
    files[path] = nil
    directories[path] = nil

    -- Also delete children if directory
    for p in pairs(files) do
        if p:sub(1, #path + 1) == path .. "/" then
            files[p] = nil
        end
    end
    for p in pairs(directories) do
        if p:sub(1, #path + 1) == path .. "/" then
            directories[p] = nil
        end
    end
end

-- Move file/directory
function Fs.move(from, to)
    from = Fs.normalize(from)
    to = Fs.normalize(to)

    if files[from] then
        files[to] = files[from]
        files[from] = nil
    elseif directories[from] then
        directories[to] = true
        directories[from] = nil
    end
end

-- Copy file/directory
function Fs.copy(from, to)
    from = Fs.normalize(from)
    to = Fs.normalize(to)

    if files[from] then
        files[to] = files[from]
    end
end

-- List directory contents
function Fs.list(path)
    path = Fs.normalize(path)
    local result = {}
    local seen = {}

    local prefix = path == "/" and "/" or path .. "/"

    for p in pairs(files) do
        if p:sub(1, #prefix) == prefix then
            local rest = p:sub(#prefix + 1)
            local name = rest:match("^([^/]+)")
            if name and not seen[name] then
                seen[name] = true
                table.insert(result, name)
            end
        end
    end

    for p in pairs(directories) do
        if p:sub(1, #prefix) == prefix then
            local rest = p:sub(#prefix + 1)
            local name = rest:match("^([^/]+)")
            if name and not seen[name] then
                seen[name] = true
                table.insert(result, name)
            end
        end
    end

    table.sort(result)
    return result
end

-- Open file for reading/writing
-- CC:Tweaked modes: "r", "w", "a", "rb", "wb", "ab"
function Fs.open(path, mode)
    path = Fs.normalize(path)
    mode = mode or "r"

    if mode == "r" then
        -- Read mode
        if not files[path] then
            return nil, "File not found"
        end

        local content = files[path]
        local pos = 1

        return {
            readLine = function(withTrailing)
                if pos > #content then return nil end
                local lineEnd = content:find("\n", pos, true)
                local line
                if lineEnd then
                    line = content:sub(pos, lineEnd - 1)
                    pos = lineEnd + 1
                else
                    line = content:sub(pos)
                    pos = #content + 1
                end
                if withTrailing and lineEnd then
                    line = line .. "\n"
                end
                return line
            end,
            readAll = function()
                local result = content:sub(pos)
                pos = #content + 1
                return result
            end,
            read = function(count)
                if pos > #content then return nil end
                count = count or 1
                local result = content:sub(pos, pos + count - 1)
                pos = pos + count
                return result
            end,
            close = function() end
        }

    elseif mode == "w" then
        -- Write mode (truncate)
        local buffer = {}

        return {
            write = function(text)
                table.insert(buffer, text)
            end,
            writeLine = function(text)
                table.insert(buffer, text)
                table.insert(buffer, "\n")
            end,
            flush = function()
                files[path] = table.concat(buffer)
            end,
            close = function()
                files[path] = table.concat(buffer)
            end
        }

    elseif mode == "a" then
        -- Append mode
        local existing = files[path] or ""
        local buffer = {existing}

        return {
            write = function(text)
                table.insert(buffer, text)
            end,
            writeLine = function(text)
                table.insert(buffer, text)
                table.insert(buffer, "\n")
            end,
            flush = function()
                files[path] = table.concat(buffer)
            end,
            close = function()
                files[path] = table.concat(buffer)
            end
        }

    elseif mode == "rb" then
        -- Binary read
        if not files[path] then
            return nil, "File not found"
        end

        local content = files[path]
        local pos = 1

        return {
            read = function(count)
                if pos > #content then return nil end
                count = count or 1
                local result = content:sub(pos, pos + count - 1)
                pos = pos + count
                return result
            end,
            readAll = function()
                local result = content:sub(pos)
                pos = #content + 1
                return result
            end,
            close = function() end
        }

    elseif mode == "wb" or mode == "ab" then
        -- Binary write/append
        local existing = (mode == "ab" and files[path]) or ""
        local buffer = {existing}

        return {
            write = function(data)
                table.insert(buffer, data)
            end,
            flush = function()
                files[path] = table.concat(buffer)
            end,
            close = function()
                files[path] = table.concat(buffer)
            end
        }
    end

    return nil, "Invalid mode: " .. mode
end

-- Get free space (always returns large number in mock)
function Fs.getFreeSpace(path)
    return 1000000000
end

-- Get capacity (always returns large number in mock)
function Fs.getCapacity(path)
    return 1000000000
end

-- Test helpers
function Fs.writeFile(path, content)
    path = Fs.normalize(path)
    files[path] = content
    -- Ensure parent directory exists
    local parent = Fs.getDir(path)
    if parent ~= "/" then
        directories[parent] = true
    end
end

function Fs.readFile(path)
    path = Fs.normalize(path)
    return files[path]
end

function Fs.getFiles()
    return files
end

function Fs.getDirectories()
    return directories
end

-- Install into global _G.fs
function Fs.install()
    _G.fs = {
        exists = Fs.exists,
        isDir = Fs.isDir,
        getSize = Fs.getSize,
        combine = Fs.combine,
        getDir = Fs.getDir,
        getName = Fs.getName,
        makeDir = Fs.makeDir,
        delete = Fs.delete,
        move = Fs.move,
        copy = Fs.copy,
        list = Fs.list,
        open = Fs.open,
        getFreeSpace = Fs.getFreeSpace,
        getCapacity = Fs.getCapacity,
        -- Test helpers exposed for convenience
        _writeFile = Fs.writeFile,
        _readFile = Fs.readFile,
        _reset = Fs.reset
    }
end

return Fs
