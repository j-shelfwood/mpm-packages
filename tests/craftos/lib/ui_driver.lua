local UIDriver = {}
UIDriver.__index = UIDriver

local function rtrim(s)
    return (s:gsub("%s+$", ""))
end

function UIDriver.new(width, height)
    local self = setmetatable({}, UIDriver)

    self.width = width or 51
    self.height = height or 19
    self.parent = term.native and term.native() or term.current()
    self.buffer = window.create(self.parent, 1, 1, self.width, self.height, false)
    self.previous = term.current()

    term.redirect(self.buffer)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)

    return self
end

function UIDriver:close()
    if self.previous then
        term.redirect(self.previous)
        self.previous = nil
    end
end

function UIDriver:line(y)
    local text = select(1, self.buffer.getLine(y))
    if not text then
        return ""
    end
    return rtrim(text)
end

function UIDriver:lines()
    local out = {}
    for y = 1, self.height do
        out[#out + 1] = self:line(y)
    end
    return out
end

function UIDriver:snapshot()
    return table.concat(self:lines(), "\n")
end

function UIDriver:contains(needle)
    for _, line in ipairs(self:lines()) do
        if line:find(needle, 1, true) then
            return true
        end
    end
    return false
end

function UIDriver:key_code(name)
    local code = keys[name]
    if not code then
        error("Unknown key name: " .. tostring(name))
    end
    return code
end

function UIDriver:key_event(name)
    return { "key", self:key_code(name), false }
end

return UIDriver
