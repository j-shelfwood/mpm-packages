-- TouchZones.lua
-- Region-based touch handling for monitors
-- Defines clickable zones and routes touch events to handlers

local TouchZones = {}
TouchZones.__index = TouchZones

-- Create a new TouchZones manager for a monitor
-- @param monitor The monitor peripheral
-- @return TouchZones instance
function TouchZones.new(monitor)
    if not monitor then
        error("TouchZones requires a monitor peripheral")
    end

    local self = setmetatable({}, TouchZones)
    self.monitor = monitor
    self.monitorName = peripheral.getName(monitor)
    self.zones = {}
    self.width, self.height = monitor.getSize()

    return self
end

-- Define a touch zone
-- @param id Unique identifier for this zone
-- @param x1, y1 Top-left corner (1-indexed)
-- @param x2, y2 Bottom-right corner (1-indexed)
-- @param handler Function to call when zone is touched: handler(x, y, zoneId)
function TouchZones:addZone(id, x1, y1, x2, y2, handler)
    if type(handler) ~= "function" then
        error("Zone handler must be a function")
    end

    self.zones[id] = {
        x1 = math.min(x1, x2),
        y1 = math.min(y1, y2),
        x2 = math.max(x1, x2),
        y2 = math.max(y1, y2),
        handler = handler
    }
end

-- Remove a zone by id
function TouchZones:removeZone(id)
    self.zones[id] = nil
end

-- Clear all zones
function TouchZones:clear()
    self.zones = {}
end

-- Add standard navigation zones (left/right halves)
-- @param onPrev Handler for left side touch
-- @param onNext Handler for right side touch
function TouchZones:addNavigationZones(onPrev, onNext)
    local halfWidth = math.floor(self.width / 2)

    self:addZone("nav_prev", 1, 1, halfWidth, self.height, onPrev)
    self:addZone("nav_next", halfWidth + 1, 1, self.width, self.height, onNext)
end

-- Add a config button zone at bottom center
-- @param handler Handler for config button
-- @param label Optional label text (default: "Config")
function TouchZones:addConfigZone(handler, label)
    label = label or "Config"
    local labelWidth = #label + 4
    local startX = math.floor((self.width - labelWidth) / 2) + 1

    self:addZone("config", startX, self.height, startX + labelWidth - 1, self.height, handler)
end

-- Check if a point is within a zone
-- @param x, y Touch coordinates
-- @return zoneId or nil
function TouchZones:getZoneAt(x, y)
    for id, zone in pairs(self.zones) do
        if x >= zone.x1 and x <= zone.x2 and y >= zone.y1 and y <= zone.y2 then
            return id
        end
    end
    return nil
end

-- Handle a single touch event
-- @param monitorName The monitor that was touched
-- @param x, y Touch coordinates
-- @return true if handled, false if no zone matched
function TouchZones:handleTouch(monitorName, x, y)
    if monitorName ~= self.monitorName then
        return false
    end

    local zoneId = self:getZoneAt(x, y)
    if zoneId then
        local zone = self.zones[zoneId]
        zone.handler(x, y, zoneId)
        return true
    end

    return false
end

-- Process a monitor_touch event
-- @param event The event table {event, monitorName, x, y}
-- @return true if handled
function TouchZones:processEvent(event, p1, p2, p3)
    if event == "monitor_touch" then
        return self:handleTouch(p1, p2, p3)
    end
    return false
end

-- Update monitor dimensions (call after text scale changes)
function TouchZones:updateDimensions()
    self.width, self.height = self.monitor.getSize()
end

-- Get zone boundaries for debugging/visualization
function TouchZones:getZoneBounds(id)
    local zone = self.zones[id]
    if zone then
        return zone.x1, zone.y1, zone.x2, zone.y2
    end
    return nil
end

-- List all zone IDs
function TouchZones:listZones()
    local ids = {}
    for id in pairs(self.zones) do
        table.insert(ids, id)
    end
    return ids
end

return TouchZones
