-- Discovery.lua
-- Service advertisement and discovery for ShelfOS zones

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
    self.zoneId = nil
    self.zoneName = nil
    self.knownZones = {}
    self.lastAnnounce = 0
    self.announceInterval = 30000  -- 30 seconds

    return self
end

-- Initialize with zone identity
-- @param zoneId Unique zone identifier
-- @param zoneName Human-readable zone name
function Discovery:setIdentity(zoneId, zoneName)
    self.zoneId = zoneId
    self.zoneName = zoneName
end

-- Start discovery service (opens channel if needed)
function Discovery:start()
    if not self.channel then
        self.channel = Channel.new()
        local ok = self.channel:open(true)  -- Prefer ender
        if not ok then
            return false, "No modem available"
        end
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

-- Handle zone announcement (rich metadata from peers)
function Discovery:handleAnnounce(senderId, msg)
    if msg.data and msg.data.zoneId then
        self:registerZone(senderId, msg.data.zoneId, msg.data.zoneName, msg.data.monitors)
    end
end

-- Handle discovery request
function Discovery:handleDiscover(senderId, msg)
    -- Respond with our announcement
    self:announce()
end

-- Register a discovered zone
function Discovery:registerZone(computerId, zoneId, zoneName, monitors)
    self.knownZones[zoneId] = {
        computerId = computerId,
        zoneId = zoneId,
        zoneName = zoneName or zoneId,
        monitors = monitors or {},
        lastSeen = os.epoch("utc")
    }
end

-- Announce this zone's presence
function Discovery:announce(monitors)
    if not self.zoneId or not self.channel then return end

    local msg = Protocol.createAnnounce(self.zoneId, self.zoneName, monitors)
    self.channel:broadcast(msg)
    self.lastAnnounce = os.epoch("utc")
end

-- Discover other zones using native rednet.lookup + rich metadata request
-- @param timeout How long to wait for responses
-- @return Array of discovered zones
function Discovery:discover(timeout)
    timeout = timeout or 3

    -- First, use native CC:Tweaked service discovery
    local peerIds = {rednet.lookup("shelfos")}

    if #peerIds > 0 then
        -- Request rich metadata from discovered peers
        local discoverMsg = Protocol.createMessage(Protocol.MessageType.DISCOVER, {
            zoneId = self.zoneId,
            zoneName = self.zoneName
        })

        -- Broadcast discover request (peers will respond with ANNOUNCE)
        if self.channel then
            self.channel:broadcast(discoverMsg)

            -- Collect responses
            local deadline = os.epoch("utc") + (timeout * 1000)
            while os.epoch("utc") < deadline do
                self.channel:poll(0.1)
            end
        end
    end

    -- Return known zones (populated by ANNOUNCE responses)
    return self:getZones()
end

-- Get list of known zones
function Discovery:getZones()
    local zones = {}
    local now = os.epoch("utc")
    local maxAge = 120000  -- 2 minutes

    for id, zone in pairs(self.knownZones) do
        if now - zone.lastSeen < maxAge then
            table.insert(zones, zone)
        end
    end

    return zones
end

-- Get a specific zone by ID
function Discovery:getZone(zoneId)
    return self.knownZones[zoneId]
end

-- Check if should re-announce (for periodic announcements)
function Discovery:shouldAnnounce()
    return os.epoch("utc") - self.lastAnnounce > self.announceInterval
end

-- Clean up stale zones
function Discovery:cleanup()
    local now = os.epoch("utc")
    local maxAge = 300000  -- 5 minutes

    for id, zone in pairs(self.knownZones) do
        if now - zone.lastSeen > maxAge then
            self.knownZones[id] = nil
        end
    end
end

-- Lookup zones by name (partial match)
function Discovery:findByName(namePattern)
    local results = {}
    local pattern = namePattern:lower()

    for _, zone in pairs(self.knownZones) do
        if zone.zoneName:lower():find(pattern) then
            table.insert(results, zone)
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
