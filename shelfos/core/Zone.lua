-- Zone.lua
-- Zone identity and coordination

local Zone = {}
Zone.__index = Zone

-- Create a new zone
-- @param config Zone configuration from shelfos.config
function Zone.new(config)
    config = config or {}

    local self = setmetatable({}, Zone)
    self.id = config.id or ("zone_" .. os.getComputerID())
    self.name = config.name or ("Zone " .. os.getComputerID())
    self.computerId = os.getComputerID()
    self.label = os.getComputerLabel() or self.name

    return self
end

-- Get zone ID
function Zone:getId()
    return self.id
end

-- Get zone name
function Zone:getName()
    return self.name
end

-- Set zone name
function Zone:setName(name)
    self.name = name
end

-- Get computer ID
function Zone:getComputerId()
    return self.computerId
end

-- Get computer label
function Zone:getLabel()
    return self.label
end

-- Generate a unique zone ID
function Zone.generateId()
    return string.format("zone_%d_%d", os.getComputerID(), os.epoch("utc") % 100000)
end

-- Get zone info for network messages
function Zone:getInfo()
    return {
        id = self.id,
        name = self.name,
        computerId = self.computerId,
        label = self.label
    }
end

return Zone
