local Influx = {}
Influx.__index = Influx

local function escapeTag(value)
    return tostring(value)
        :gsub("\\", "\\\\")
        :gsub(" ", "\\ ")
        :gsub(",", "\\,")
        :gsub("=", "\\=")
end

local function escapeMeasurement(value)
    return tostring(value)
        :gsub("\\", "\\\\")
        :gsub(" ", "\\ ")
        :gsub(",", "\\,")
end

local function formatFieldValue(value)
    if type(value) == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return nil
        end
        return tostring(value)
    end
    if type(value) == "boolean" then
        return value and "true" or "false"
    end
    return nil
end

local function encodeComponent(value)
    return tostring(value):gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

local function nowMs()
    return os.epoch("utc")
end

function Influx.new(config)
    local self = setmetatable({}, Influx)
    self.config = config
    self.buffer = {}
    self.nextFlushAt = 0
    self.backoffSeconds = 0
    self.lastError = nil
    return self
end

function Influx:buildWriteUrl()
    local base = self.config.url or ""
    base = base:gsub("/+$", "")
    return string.format(
        "%s/api/v2/write?org=%s&bucket=%s&precision=ms",
        base,
        encodeComponent(self.config.org),
        encodeComponent(self.config.bucket)
    )
end

function Influx:add(measurement, tags, fields, timestampMs)
    if type(fields) ~= "table" then
        return
    end

    local fieldParts = {}
    for key, value in pairs(fields) do
        local encoded = formatFieldValue(value)
        if encoded then
            table.insert(fieldParts, string.format("%s=%s", escapeTag(key), encoded))
        end
    end

    if #fieldParts == 0 then
        return
    end

    local tagParts = {}
    if type(tags) == "table" then
        for key, value in pairs(tags) do
            if value ~= nil and value ~= "" then
                table.insert(tagParts, string.format("%s=%s", escapeTag(key), escapeTag(value)))
            end
        end
    end

    table.sort(tagParts)
    table.sort(fieldParts)

    local line = escapeMeasurement(measurement)
    if #tagParts > 0 then
        line = line .. "," .. table.concat(tagParts, ",")
    end
    line = line .. " " .. table.concat(fieldParts, ",")
    if timestampMs then
        line = line .. " " .. tostring(timestampMs)
    end

    table.insert(self.buffer, line)

    if #self.buffer > (self.config.max_buffer_lines or 5000) then
        while #self.buffer > (self.config.max_buffer_lines or 5000) do
            table.remove(self.buffer, 1)
        end
    end
end

function Influx:flush(force)
    if #self.buffer == 0 then
        return true
    end

    local now = nowMs()
    local flushIntervalMs = (self.config.flush_interval_s or 5) * 1000
    if not force and now < self.nextFlushAt then
        return true
    end

    local url = self:buildWriteUrl()
    local body = table.concat(self.buffer, "\n")
    local headers = {
        ["Authorization"] = "Token " .. tostring(self.config.token),
        ["Content-Type"] = "text/plain; charset=utf-8"
    }

    local ok, response = pcall(http.post, url, body, headers)
    if not ok or not response then
        self.lastError = "http.post failed"
        self.backoffSeconds = math.min((self.backoffSeconds == 0 and 5) or (self.backoffSeconds * 2), 60)
        self.nextFlushAt = now + (self.backoffSeconds * 1000)
        return false
    end

    local status = response.getResponseCode and response.getResponseCode() or 0
    local respBody = response.readAll and response.readAll() or ""
    response.close()

    if status < 200 or status >= 300 then
        self.lastError = string.format("Influx write failed (%d): %s", status, respBody)
        self.backoffSeconds = math.min((self.backoffSeconds == 0 and 5) or (self.backoffSeconds * 2), 60)
        self.nextFlushAt = now + (self.backoffSeconds * 1000)
        return false
    end

    self.buffer = {}
    self.lastError = nil
    self.backoffSeconds = 0
    self.nextFlushAt = now + flushIntervalMs
    return true
end

function Influx:flushIfDue()
    return self:flush(false)
end

return Influx
