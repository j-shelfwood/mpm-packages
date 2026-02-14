-- Identity.lua
-- Computer identity and coordination
-- (Renamed from Zone.lua - "Identity" avoids confusion with CC:Tweaked's "computer" peripheral type)

local Identity = {}
Identity.__index = Identity

-- Create a new identity
-- @param config Computer configuration from shelfos.config
function Identity.new(config)
    config = config or {}

    local self = setmetatable({}, Identity)
    self.id = config.id or ("computer_" .. os.getComputerID())
    self.name = config.name or ("Computer " .. os.getComputerID())
    self.computerId = os.getComputerID()
    self.label = os.getComputerLabel() or self.name

    return self
end

-- Get identity ID
function Identity:getId()
    return self.id
end

-- Get computer name
function Identity:getName()
    return self.name
end

-- Set computer name
function Identity:setName(name)
    self.name = name
end

-- Get computer ID
function Identity:getComputerId()
    return self.computerId
end

-- Get computer label
function Identity:getLabel()
    return self.label
end

-- Generate a unique computer ID
function Identity.generateId()
    return string.format("computer_%d_%d", os.getComputerID(), os.epoch("utc") % 100000)
end

-- Get identity info for network messages
function Identity:getInfo()
    return {
        id = self.id,
        name = self.name,
        computerId = self.computerId,
        label = self.label
    }
end

return Identity
