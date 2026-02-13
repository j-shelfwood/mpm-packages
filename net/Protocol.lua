-- Protocol.lua
-- ShelfOS message protocol definitions
-- Defines message types and validation

local Protocol = {}

-- Protocol identifier
Protocol.PROTOCOL = "shelfos"

-- Message types
Protocol.MessageType = {
    -- Discovery
    PING = "ping",
    PONG = "pong",
    ANNOUNCE = "announce",
    DISCOVER = "discover",

    -- Zone coordination
    ZONE_STATUS = "zone_status",
    ZONE_LIST = "zone_list",

    -- View management
    GET_VIEWS = "get_views",
    VIEWS_LIST = "views_list",
    SET_VIEW = "set_view",
    VIEW_CHANGED = "view_changed",

    -- Configuration
    GET_CONFIG = "get_config",
    CONFIG_DATA = "config_data",
    SET_CONFIG = "set_config",
    CONFIG_UPDATED = "config_updated",

    -- Input relay (pocket → zone)
    INPUT_REQUEST = "input_request",
    INPUT_RESPONSE = "input_response",
    INPUT_CANCEL = "input_cancel",

    -- Alerts (zone → pocket)
    ALERT = "alert",
    ALERT_ACK = "alert_ack",

    -- Remote Peripherals (ender modem proxy)
    PERIPH_DISCOVER = "periph_discover",    -- Request list of peripherals
    PERIPH_LIST = "periph_list",            -- Response with peripheral list
    PERIPH_ANNOUNCE = "periph_announce",    -- Broadcast available peripherals
    PERIPH_CALL = "periph_call",            -- Call method on remote peripheral
    PERIPH_RESULT = "periph_result",        -- Result of peripheral call
    PERIPH_ERROR = "periph_error",          -- Error from peripheral call

    -- Pocket Pairing (bootstrap without crypto)
    PAIR_READY = "pair_ready",              -- Computer → Pocket: ready to receive secret
    PAIR_DELIVER = "pair_deliver",          -- Pocket → Computer: delivering swarm secret
    PAIR_COMPLETE = "pair_complete",        -- Computer → Pocket: pairing successful
    PAIR_REJECT = "pair_reject",            -- Either direction: pairing cancelled

    -- System
    ERROR = "error",
    OK = "ok"
}

-- Alert levels
Protocol.AlertLevel = {
    INFO = "info",
    WARNING = "warning",
    ERROR = "error",
    CRITICAL = "critical"
}

-- Create a message
-- @param msgType Message type from Protocol.MessageType
-- @param data Message payload
-- @param requestId Optional request ID for request/response correlation
-- @return Message table
function Protocol.createMessage(msgType, data, requestId)
    return {
        type = msgType,
        data = data or {},
        requestId = requestId or nil,
        timestamp = os.epoch("utc")
    }
end

-- Create a response to a request
-- @param request Original request message
-- @param msgType Response message type
-- @param data Response data
-- @return Response message
function Protocol.createResponse(request, msgType, data)
    return Protocol.createMessage(msgType, data, request.requestId)
end

-- Create an error response
-- @param request Original request (or nil)
-- @param errorMessage Error description
-- @return Error message
function Protocol.createError(request, errorMessage)
    return Protocol.createMessage(
        Protocol.MessageType.ERROR,
        {error = errorMessage},
        request and request.requestId
    )
end

-- Create a ping message
-- @param zoneId This zone's ID
-- @return Ping message
function Protocol.createPing(zoneId)
    return Protocol.createMessage(Protocol.MessageType.PING, {
        zoneId = zoneId
    })
end

-- Create a pong response
-- @param ping The ping message
-- @param zoneId This zone's ID
-- @param zoneName This zone's name
-- @return Pong message
function Protocol.createPong(ping, zoneId, zoneName)
    return Protocol.createResponse(ping, Protocol.MessageType.PONG, {
        zoneId = zoneId,
        zoneName = zoneName
    })
end

-- Create an announce message (zone advertising itself)
-- @param zoneId Zone ID
-- @param zoneName Zone name
-- @param monitors Array of monitor info
-- @return Announce message
function Protocol.createAnnounce(zoneId, zoneName, monitors)
    return Protocol.createMessage(Protocol.MessageType.ANNOUNCE, {
        zoneId = zoneId,
        zoneName = zoneName,
        monitors = monitors or {}
    })
end

-- Create an alert message
-- @param level Alert level from Protocol.AlertLevel
-- @param title Alert title
-- @param message Alert message
-- @param source Source zone/monitor
-- @return Alert message
function Protocol.createAlert(level, title, message, source)
    return Protocol.createMessage(Protocol.MessageType.ALERT, {
        level = level,
        title = title,
        message = message,
        source = source
    })
end

-- Create an input request (zone asking pocket for text input)
-- @param field Field name
-- @param fieldType Field type (string, number)
-- @param currentValue Current value
-- @param constraints Validation constraints
-- @return Input request message
function Protocol.createInputRequest(field, fieldType, currentValue, constraints)
    return Protocol.createMessage(Protocol.MessageType.INPUT_REQUEST, {
        field = field,
        fieldType = fieldType,
        currentValue = currentValue,
        constraints = constraints or {}
    })
end

-- Create an input response
-- @param request Original request
-- @param value The entered value
-- @return Input response message
function Protocol.createInputResponse(request, value)
    return Protocol.createResponse(request, Protocol.MessageType.INPUT_RESPONSE, {
        value = value
    })
end

-- Validate a message structure
-- @param msg Message to validate
-- @return valid (boolean), error (string or nil)
function Protocol.validate(msg)
    if type(msg) ~= "table" then
        return false, "Message is not a table"
    end

    if not msg.type then
        return false, "Message missing type"
    end

    if not msg.timestamp then
        return false, "Message missing timestamp"
    end

    -- Check type is known
    local typeValid = false
    for _, t in pairs(Protocol.MessageType) do
        if msg.type == t then
            typeValid = true
            break
        end
    end

    if not typeValid then
        return false, "Unknown message type: " .. tostring(msg.type)
    end

    return true, nil
end

-- Check if message is a request (expects response)
function Protocol.isRequest(msg)
    local requestTypes = {
        [Protocol.MessageType.PING] = true,
        [Protocol.MessageType.DISCOVER] = true,
        [Protocol.MessageType.GET_VIEWS] = true,
        [Protocol.MessageType.GET_CONFIG] = true,
        [Protocol.MessageType.SET_VIEW] = true,
        [Protocol.MessageType.SET_CONFIG] = true,
        [Protocol.MessageType.INPUT_REQUEST] = true,
        [Protocol.MessageType.PERIPH_DISCOVER] = true,
        [Protocol.MessageType.PERIPH_CALL] = true
    }
    return requestTypes[msg.type] == true
end

-- Create peripheral discovery request
function Protocol.createPeriphDiscover()
    return Protocol.createMessage(Protocol.MessageType.PERIPH_DISCOVER, {})
end

-- Create peripheral list response
-- @param peripherals Array of {name, type, methods}
function Protocol.createPeriphList(request, peripherals)
    return Protocol.createResponse(request, Protocol.MessageType.PERIPH_LIST, {
        peripherals = peripherals
    })
end

-- Create peripheral announcement (broadcast)
-- @param zoneId Zone identifier
-- @param peripherals Array of {name, type, methods}
function Protocol.createPeriphAnnounce(zoneId, zoneName, peripherals)
    return Protocol.createMessage(Protocol.MessageType.PERIPH_ANNOUNCE, {
        zoneId = zoneId,
        zoneName = zoneName,
        peripherals = peripherals
    })
end

-- Create peripheral method call
-- @param peripheralName Name of the peripheral
-- @param methodName Method to call
-- @param args Arguments table
function Protocol.createPeriphCall(peripheralName, methodName, args)
    return Protocol.createMessage(Protocol.MessageType.PERIPH_CALL, {
        peripheral = peripheralName,
        method = methodName,
        args = args or {}
    })
end

-- Create peripheral result response
-- @param request Original call request
-- @param results Results table (array of return values)
function Protocol.createPeriphResult(request, results)
    return Protocol.createResponse(request, Protocol.MessageType.PERIPH_RESULT, {
        results = results
    })
end

-- Create peripheral error response
-- @param request Original call request
-- @param errorMsg Error message
function Protocol.createPeriphError(request, errorMsg)
    return Protocol.createResponse(request, Protocol.MessageType.PERIPH_ERROR, {
        error = errorMsg
    })
end

-- Check if message is a response
function Protocol.isResponse(msg)
    return msg.requestId ~= nil
end

-- ============================================================================
-- Pocket Pairing Messages (bootstrap without crypto)
-- ============================================================================

-- Create pair ready message (computer broadcasts when ready to receive secret)
-- @param token One-time token for verification
-- @param computerLabel Computer label/name
-- @param computerId Computer ID
-- @return Pair ready message
function Protocol.createPairReady(token, computerLabel, computerId)
    return Protocol.createMessage(Protocol.MessageType.PAIR_READY, {
        token = token,
        label = computerLabel or ("Computer #" .. (computerId or "?")),
        computerId = computerId
    })
end

-- Create pair deliver message (pocket sends swarm secret to computer)
-- @param token The token from PAIR_READY (for verification)
-- @param secret The swarm secret
-- @param pairingCode The swarm pairing code
-- @param zoneId Zone ID to join
-- @param zoneName Zone name
-- @return Pair deliver message
function Protocol.createPairDeliver(token, secret, pairingCode, zoneId, zoneName)
    return Protocol.createMessage(Protocol.MessageType.PAIR_DELIVER, {
        token = token,
        secret = secret,
        pairingCode = pairingCode,
        zoneId = zoneId,
        zoneName = zoneName
    })
end

-- Create pair complete message (computer confirms successful pairing)
-- @param computerLabel Computer label after joining
-- @return Pair complete message
function Protocol.createPairComplete(computerLabel)
    return Protocol.createMessage(Protocol.MessageType.PAIR_COMPLETE, {
        label = computerLabel,
        success = true
    })
end

-- Create pair reject message (either side cancels pairing)
-- @param reason Rejection reason
-- @return Pair reject message
function Protocol.createPairReject(reason)
    return Protocol.createMessage(Protocol.MessageType.PAIR_REJECT, {
        reason = reason or "Cancelled"
    })
end

return Protocol
