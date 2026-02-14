local root = _G.TEST_ROOT or "."
local Protocol = dofile(root .. "/net/Protocol.lua")

local function assert_true(value, message)
    if not value then
        error(message or "expected true")
    end
end

local function assert_false(value, message)
    if value then
        error(message or "expected false")
    end
end

local function assert_eq(expected, actual, message)
    if expected ~= actual then
        error((message or "values differ") .. string.format(" (expected=%s actual=%s)", tostring(expected), tostring(actual)))
    end
end

test("Protocol.createRequest sets requestId", function()
    local msg = Protocol.createRequest(Protocol.MessageType.GET_CONFIG, { zoneId = "z1" })
    assert_true(type(msg.requestId) == "string" and #msg.requestId > 0, "requestId should be generated")
    assert_eq(Protocol.MessageType.GET_CONFIG, msg.type)
end)

test("Protocol.createResponse keeps requestId", function()
    local req = Protocol.createRequest(Protocol.MessageType.GET_CONFIG, {})
    local resp = Protocol.createResponse(req, Protocol.MessageType.CONFIG_DATA, { ok = true })
    assert_eq(req.requestId, resp.requestId)
    assert_eq(Protocol.MessageType.CONFIG_DATA, resp.type)
end)

test("Protocol.validate rejects malformed message", function()
    local ok, err = Protocol.validate({ timestamp = 123 })
    assert_false(ok)
    assert_true(type(err) == "string" and #err > 0)
end)

test("Protocol.validate accepts known type", function()
    local msg = Protocol.createMessage(Protocol.MessageType.PING, {})
    local ok, err = Protocol.validate(msg)
    assert_true(ok, err)
end)

test("Protocol.isRequest classification", function()
    assert_true(Protocol.isRequest({ type = Protocol.MessageType.GET_VIEWS }))
    assert_false(Protocol.isRequest({ type = Protocol.MessageType.PONG }))
end)
