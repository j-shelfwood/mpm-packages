-- Discovery.lua
-- Service advertisement and discovery for ShelfOS computers

local Channel = mpm('net/Channel')
local Protocol = mpm('net/Protocol')

local Discovery = {}
Discovery.__index = Discovery

-- Create a new discovery service
-- @param channel Optional existing channel to use
-- @return Discovery instance
function Discovery.new(channel)
    local self = setmetatable({}, Discovery)
    self.channel = channel
    self.ownsChannel = false
    self.computerId = nil
    self.computerName = nil
    self.knownComputers = {}
    self.lastAnnounce = 0
    self.announceInterval = 30000  -- 30 seconds

    return self
end

-- Initialize with computer identity
-- @param computerId Unique computer identifier
-- @param computerName Human-readable computer name
function Discovery:setIdentity(computerId, computerName)
    self.computerId = computerId
    self.computerName = computerName
end

-- Start discovery service (opens channel if needed)
function Discovery:start()
    if not self.channel then
        local channel = Channel.openNew(true)
        if not channel then
            return false, "No modem available"
        end
        self.channel = channel
        self.ownsChannel = true
    end

    -- Register handlers for rich metadata exchange
    -- Note: Basic presence uses native rednet.host/lookup (set up in Kernel)
    self.channel:on(Protocol.MessageType.ANNOUNCE, function(senderId, msg)
        self:handleAnnounce(senderId, msg)
    end)

    self.channel:on(Protocol.MessageType.DISCOVER, function(senderId, msg)
        self:handleDiscover(senderId, msg)
    end)

    return true
end

-- Stop discovery service
function Discovery:stop()
    if self.ownsChannel and self.channel then
        self.channel:close()
        self.channel = nil
    end
end

-- Handle computer announcement (rich metadata from peers)
function Discovery:handleAnnounce(senderId, msg)
    if msg.data and msg.data.computerId then
        self:registerComputer(senderId, msg.data.computerId, msg.data.computerName, msg.data.monitors)
    end
end

-- Handle discovery request
function Discovery:handleDiscover(senderId, msg)
    -- Respond with our announcement
    self:announce()
end

-- Register a discovered computer
function Discovery:registerComputer(ccId, computerId, computerName, monitors)
    self.knownComputers[computerId] = {
        ccId = ccId,
        computerId = computerId,
        computerName = computerName or computerId,
        monitors = monitors or {},
        lastSeen = os.epoch("utc")
    }
end

-- Announce this computer's presence
function Discovery:announce(monitors)
    if not self.computerId or not self.channel then return end

    local msg = Protocol.createAnnounce(self.computerId, self.computerName, monitors)
    self.channel:broadcast(msg)
    self.lastAnnounce = os.epoch("utc")
end

-- Discover other computers using broadcast + poll
-- Note: rednet.lookup requires computers to have called rednet.host() which only
-- happens after network init. New computers may not be in the lookup yet, so we
-- always broadcast DISCOVER to catch recently-joined computers.
-- @param timeout How long to wait for responses
-- @return Array of discovered computers
function Discovery:discover(timeout)
    timeout = timeout or 3

    -- Request rich metadata from all swarm members
    local discoverMsg = Protocol.createMessage(Protocol.MessageType.DISCOVER, {
        computerId = self.computerId,
        computerName = self.computerName
    })

    -- Broadcast discover request (peers will respond with ANNOUNCE)
    -- Always broadcast - don't skip based on rednet.lookup which may be stale
    if self.channel then
        self.channel:broadcast(discoverMsg)

        -- Collect responses
        local deadline = os.epoch("utc") + (timeout * 1000)
        while os.epoch("utc") < deadline do
            self.channel:poll(0.1)
        end
    end

    -- Return known computers (populated by ANNOUNCE responses)
    return self:getComputers()
end

-- Get list of known computers
function Discovery:getComputers()
    local computers = {}
    local now = os.epoch("utc")
    local maxAge = 120000  -- 2 minutes

    for id, computer in pairs(self.knownComputers) do
        if now - computer.lastSeen < maxAge then
            table.insert(computers, computer)
        end
    end

    return computers
end

-- Get a specific computer by ID
function Discovery:getComputer(computerId)
    return self.knownComputers[computerId]
end

-- Check if should re-announce (for periodic announcements)
function Discovery:shouldAnnounce()
    return os.epoch("utc") - self.lastAnnounce > self.announceInterval
end

-- Clean up stale computers
function Discovery:cleanup()
    local now = os.epoch("utc")
    local maxAge = 300000  -- 5 minutes

    for id, computer in pairs(self.knownComputers) do
        if now - computer.lastSeen > maxAge then
            self.knownComputers[id] = nil
        end
    end
end

-- Lookup computers by name (partial match)
function Discovery:findByName(namePattern)
    local results = {}
    local pattern = namePattern:lower()

    for _, computer in pairs(self.knownComputers) do
        if computer.computerName:lower():find(pattern) then
            table.insert(results, computer)
        end
    end

    return results
end

-- Get peer count using native rednet.lookup (fast, no metadata)
-- @return Number of ShelfOS peers on network
function Discovery:getPeerCount()
    local peerIds = {rednet.lookup("shelfos")}
    return #peerIds
end

-- Get peer IDs using native rednet.lookup
-- @return Array of computer IDs running ShelfOS
function Discovery:getPeerIds()
    return {rednet.lookup("shelfos")}
end

return Discovery
