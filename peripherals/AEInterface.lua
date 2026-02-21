-- AEInterface.lua
-- Adapter for AE2 ME Bridge peripheral (Advanced Peripherals)
-- Provides normalized API for item/fluid/energy/crafting operations
-- Supports both local and remote peripherals via Peripherals module

local Peripherals = mpm('utils/Peripherals')
local REMOTE_HEAVY_FALLBACK_TTL_MS = 3000
local LOCAL_QUERY_CACHE_TTL_MS = 250
local REMOTE_QUERY_CACHE_TTL_MS = 700

local function findBridgeLocalFirst()
    -- Prefer directly-attached peripherals to avoid remote proxy edge-cases
    -- on the host computer that physically owns the ME bridge.
    local okLocal, localBridge = pcall(function()
        if peripheral and type(peripheral.find) == "function" then
            return peripheral.find("me_bridge")
        end
        return nil
    end)
    if okLocal and localBridge then
        return localBridge
    end

    -- Fallback to unified peripheral layer (local + remote)
    if not Peripherals or type(Peripherals.find) ~= "function" then
        return nil
    end
    local ok, bridge = pcall(function()
        return Peripherals.find("me_bridge")
    end)
    if ok then
        return bridge
    end
    return nil
end

local function nowMs()
    return os.epoch("utc")
end


local function getQueryCacheTtl(self)
    return self and self.isRemote and REMOTE_QUERY_CACHE_TTL_MS or LOCAL_QUERY_CACHE_TTL_MS
end

local function getCachedQuery(self, key)
    local cache = self and self._queryCache
    if not cache then return nil end
    local entry = cache[key]
    if not entry then return nil end
    if (nowMs() - (entry.updatedAt or 0)) > getQueryCacheTtl(self) then
        cache[key] = nil
        return nil
    end
    return entry.data
end

local function setCachedQuery(self, key, data)
    self._queryCache[key] = {
        data = data,
        updatedAt = nowMs()
    }
    return data
end

local function setReadStatus(self, key, state, detail)
    self._readStatus[key] = {
        key = key,
        state = state,
        detail = detail,
        at = nowMs(),
        isRemote = self.isRemote == true
    }
end

local function statusFor(self, key)
    return self._readStatus[key] or { key = key, state = "unknown", at = 0, isRemote = self.isRemote == true }
end

local function annotateListResult(list, status)
    if type(list) ~= "table" then
        return list
    end
    list._readStatus = status
    return list
end

local function remoteHeavyFallback(self, key, fetchFn)
    if not self._remoteHeavyFallback then
        self._remoteHeavyFallback = {}
    end

    local now = nowMs()
    local entry = self._remoteHeavyFallback[key]
    if entry and (now - (entry.updatedAt or 0)) < REMOTE_HEAVY_FALLBACK_TTL_MS then
        return entry.data or {}
    end

    local ok, data = pcall(fetchFn)
    if ok and type(data) == "table" then
        self._remoteHeavyFallback[key] = {
            data = data,
            updatedAt = now
        }
        return data
    end

    if entry and type(entry.data) == "table" then
        return entry.data
    end

    return {}
end

local AEInterface = {}
AEInterface.__index = AEInterface

-- Check if ME Bridge peripheral exists (local or remote)
-- @return boolean, peripheral|nil
function AEInterface.exists()
    local p = findBridgeLocalFirst()
    return p ~= nil, p
end

-- Find ME Bridge peripheral (local or remote)
-- @return peripheral|nil
function AEInterface.find()
    return findBridgeLocalFirst()
end

-- Create new AEInterface instance
-- @param p Optional: specific peripheral to wrap. If nil, auto-detects.
-- @return AEInterface instance
-- @throws error if no ME Bridge found
function AEInterface.new(p)
    p = p or findBridgeLocalFirst()

    if not p then
        error("No ME Bridge found")
    end

    local self = setmetatable({}, AEInterface)
    self.bridge = p
    self.isRemote = type(p) == "table" and p._isRemote == true
    self.bridgeName = Peripherals.getName(p)
    self._remoteHeavyFallback = {}
    self._queryCache = {}
    self._readStatus = {}
    self._lastGood = {}
    return self
end

function AEInterface:getReadStatus(key)
    if not key then
        return self._readStatus
    end
    return statusFor(self, key)
end

-- Fetch all items from the network
-- @return array of {registryName, displayName, count, isCraftable}
function AEInterface:items()
    local cached = getCachedQuery(self, "items")
    if cached then
        return annotateListResult(cached, statusFor(self, "items"))
    end

    local raw
    if self.isRemote then
        raw = remoteHeavyFallback(self, "items", function()
            return self.bridge.getItems() or {}
        end)
        setReadStatus(self, "items", "fallback", { source = "remote_heavy_fallback" })
    else
        raw = self.bridge.getItems() or {}
        setReadStatus(self, "items", "live", { source = "direct_bridge" })
    end

    -- Normalize and consolidate by registry name
    -- ME Bridge returns: name, amount, displayName, isCraftable, fingerprint, nbt, tags
    -- Note: docs say 'amount' but some versions may use 'count' - support both
    local byId = {}
    for _, item in ipairs(raw) do
        local id = item.name  -- registry name like "minecraft:diamond"
        if id then
            local itemCount = item.amount or item.count or 0
            if byId[id] then
                byId[id].count = byId[id].count + itemCount
            else
                byId[id] = {
                    registryName = id,
                    displayName = item.displayName or id,
                    count = itemCount,
                    isCraftable = item.isCraftable or false
                }
            end
        end
    end

    -- Convert to array
    local result = {}
    for _, item in pairs(byId) do
        table.insert(result, item)
    end

    self._lastGood.items = result
    setCachedQuery(self, "items", result)
    return annotateListResult(result, statusFor(self, "items"))
end

-- Get single item by filter (more efficient than items())
-- @param filter Table with {name="minecraft:diamond"}
-- @return item table or nil
function AEInterface:getItem(filter)
    if filter and filter.name then
        for _, item in ipairs(self:items()) do
            if item.registryName == filter.name then
                return item
            end
        end
        return nil
    end

    local item = self.bridge.getItem(filter)
    if not item then return nil end

    return {
        registryName = item.name,
        displayName = item.displayName or item.name,
        count = item.amount or item.count or 0,
        isCraftable = item.isCraftable or false
    }
end

-- Fetch all fluids from the network
-- @return array of {registryName, displayName, amount}
function AEInterface:fluids()
    local cached = getCachedQuery(self, "fluids")
    if cached then
        return annotateListResult(cached, statusFor(self, "fluids"))
    end

    local raw
    if self.isRemote then
        raw = remoteHeavyFallback(self, "fluids", function()
            return self.bridge.getFluids() or {}
        end)
        setReadStatus(self, "fluids", "fallback", { source = "remote_heavy_fallback" })
    else
        raw = self.bridge.getFluids() or {}
        setReadStatus(self, "fluids", "live", { source = "direct_bridge" })
    end

    -- Consolidate by registry name
    -- ME Bridge returns: name, count, displayName, tags (fluids use 'count' not 'amount')
    local byId = {}
    for _, fluid in ipairs(raw) do
        local id = fluid.name
        if id then
            if byId[id] then
                byId[id].amount = byId[id].amount + (fluid.count or 0)
            else
                byId[id] = {
                    registryName = id,
                    displayName = fluid.displayName or id,
                    amount = fluid.count or 0
                }
            end
        end
    end

    -- Convert to array
    local result = {}
    for _, fluid in pairs(byId) do
        table.insert(result, fluid)
    end

    self._lastGood.fluids = result
    setCachedQuery(self, "fluids", result)
    return annotateListResult(result, statusFor(self, "fluids"))
end

-- Get single fluid by filter (more efficient than fluids())
-- @param filter Table with {name="minecraft:water"}
-- @return fluid table or nil
function AEInterface:getFluid(filter)
    if filter and filter.name then
        for _, fluid in ipairs(self:fluids()) do
            if fluid.registryName == filter.name then
                return fluid
            end
        end
        return nil
    end

    local fluid = self.bridge.getFluid(filter)
    if not fluid then return nil end

    return {
        registryName = fluid.name,
        displayName = fluid.displayName or fluid.name,
        amount = fluid.count or 0
    }
end

-- Get item storage capacity
-- @return {used, total, available}
function AEInterface:itemStorage()
    local data = {
        used = self.bridge.getUsedItemStorage() or 0,
        total = self.bridge.getTotalItemStorage() or 0,
        available = self.bridge.getAvailableItemStorage() or 0
    }
    self._lastGood.itemStorage = data
    setReadStatus(self, "itemStorage", "live", { source = "direct_bridge" })
    return data
end

-- Get fluid storage capacity
-- @return {used, total, available}
function AEInterface:fluidStorage()
    local data = {
        used = self.bridge.getUsedFluidStorage() or 0,
        total = self.bridge.getTotalFluidStorage() or 0,
        available = self.bridge.getAvailableFluidStorage() or 0
    }
    self._lastGood.fluidStorage = data
    setReadStatus(self, "fluidStorage", "live", { source = "direct_bridge" })
    return data
end

-- Get energy status
-- @return {stored, capacity, usage}
function AEInterface:energy()
    local data = {
        stored = self.bridge.getStoredEnergy() or 0,
        capacity = self.bridge.getEnergyCapacity() or 0,
        usage = self.bridge.getEnergyUsage() or 0
    }
    self._lastGood.energy = data
    setReadStatus(self, "energy", "live", { source = "direct_bridge" })
    return data
end

-- Get all crafting CPUs
-- @return array of {name, storage, coProcessors, isBusy}
function AEInterface:getCraftingCPUs()
    local cached = getCachedQuery(self, "craftingCPUs")
    if cached then
        return annotateListResult(cached, statusFor(self, "craftingCPUs"))
    end

    local data = self.bridge.getCraftingCPUs() or {}
    self._lastGood.craftingCPUs = data
    setReadStatus(self, "craftingCPUs", "live", { source = "direct_bridge" })
    setCachedQuery(self, "craftingCPUs", data)
    return annotateListResult(data, statusFor(self, "craftingCPUs"))
end

-- Get all active crafting tasks
-- @return array of task tables
function AEInterface:getCraftingTasks()
    local cached = getCachedQuery(self, "craftingTasks")
    if cached then
        return annotateListResult(cached, statusFor(self, "craftingTasks"))
    end

    local data = self.bridge.getCraftingTasks() or {}
    self._lastGood.craftingTasks = data
    setReadStatus(self, "craftingTasks", "live", { source = "direct_bridge" })
    setCachedQuery(self, "craftingTasks", data)
    return annotateListResult(data, statusFor(self, "craftingTasks"))
end

-- Check if item is craftable
-- @param filter Table with {name="minecraft:diamond"}
-- @return boolean
function AEInterface:isCraftable(filter)
    return self.bridge.isCraftable(filter) or false
end

-- Request item crafting
-- @param filter Table with {name="...", count=N}
-- @param cpuName Optional CPU name
-- @return job table or nil, error
function AEInterface:craftItem(filter, cpuName)
    return self.bridge.craftItem(filter, cpuName)
end

-- Export item to adjacent inventory
-- @param filter Table with {name="...", count=N}
-- @param direction "top", "bottom", "north", "south", "east", "west" or peripheral name
-- @return number of items exported
function AEInterface:exportItem(filter, direction)
    return self.bridge.exportItem(filter, direction) or 0
end

-- Import item from adjacent inventory
-- @param filter Table with {name="...", count=N}
-- @param direction "top", "bottom", "north", "south", "east", "west" or peripheral name
-- @return number of items imported
function AEInterface:importItem(filter, direction)
    return self.bridge.importItem(filter, direction) or 0
end

-- Get storage cells
-- @return array of cell tables
function AEInterface:getCells()
    local data = self.bridge.getCells() or {}
    self._lastGood.cells = data
    setReadStatus(self, "cells", "live", { source = "direct_bridge" })
    return annotateListResult(data, statusFor(self, "cells"))
end

-- Get ME drives
-- @return array of drive tables
function AEInterface:getDrives()
    local data = self.bridge.getDrives() or {}
    self._lastGood.drives = data
    setReadStatus(self, "drives", "live", { source = "direct_bridge" })
    return annotateListResult(data, statusFor(self, "drives"))
end

-- Get crafting patterns
-- @return array of pattern tables
function AEInterface:getPatterns()
    local data = self.bridge.getPatterns() or {}
    self._lastGood.patterns = data
    setReadStatus(self, "patterns", "live", { source = "direct_bridge" })
    return annotateListResult(data, statusFor(self, "patterns"))
end

-- Get craftable items
-- @return array of craftable item tables
function AEInterface:getCraftableItems()
    local data = self.bridge.getCraftableItems() or {}
    self._lastGood.craftableItems = data
    setReadStatus(self, "craftableItems", "live", { source = "direct_bridge" })
    return annotateListResult(data, statusFor(self, "craftableItems"))
end

-- Get average energy input
-- @return number AE/t input rate
function AEInterface:getAverageEnergyInput()
    local value = self.bridge.getAverageEnergyInput() or 0
    self._lastGood.averageEnergyInput = value
    setReadStatus(self, "averageEnergyInput", "live", { source = "direct_bridge" })
    return value
end

-- Get chemicals (requires Applied Mekanistics)
-- @return array of chemical tables, or empty if not supported
function AEInterface:chemicals()
    if not self.bridge.getChemicals then
        setReadStatus(self, "chemicals", "unsupported", { source = "bridge_missing_method" })
        return annotateListResult({}, statusFor(self, "chemicals"))
    end

    local cached = getCachedQuery(self, "chemicals")
    if cached then
        return annotateListResult(cached, statusFor(self, "chemicals"))
    end

    local raw
    if self.isRemote then
        raw = remoteHeavyFallback(self, "chemicals", function()
            return self.bridge.getChemicals() or {}
        end)
        setReadStatus(self, "chemicals", "fallback", { source = "remote_heavy_fallback" })
    else
        raw = self.bridge.getChemicals() or {}
        setReadStatus(self, "chemicals", "live", { source = "direct_bridge" })
    end
    local result = {}

    for _, chem in ipairs(raw) do
        table.insert(result, {
            registryName = chem.name,
            displayName = chem.displayName or chem.name,
            amount = chem.count or chem.amount or 0
        })
    end

    self._lastGood.chemicals = result
    setCachedQuery(self, "chemicals", result)
    return annotateListResult(result, statusFor(self, "chemicals"))
end

-- Check if chemicals are supported (Applied Mekanistics loaded)
function AEInterface:hasChemicalSupport()
    return self.bridge.getChemicals ~= nil
end

-- Unified storage accessor using StorageType constants
-- @param storageType StorageType.ITEMS, StorageType.FLUIDS, or StorageType.CHEMICALS
-- @param external boolean - if true, get external storage stats
-- @return {used, total, available} or nil if type not supported
function AEInterface:getStorage(storageType, external)
    local StorageType = mpm('peripherals/StorageType')

    if not StorageType.isValid(storageType) then
        error("Invalid storage type: " .. tostring(storageType))
    end

    if not external then
        if storageType == StorageType.ITEMS then
            return self:itemStorage()
        elseif storageType == StorageType.FLUIDS then
            return self:fluidStorage()
        end
    end

    local prefix = external and "External" or ""
    local suffix = ""

    if storageType == StorageType.ITEMS then
        suffix = "Item"
    elseif storageType == StorageType.FLUIDS then
        suffix = "Fluid"
    elseif storageType == StorageType.CHEMICALS then
        suffix = "Chemical"
    end

    -- Build method names
    local usedMethod = "getUsed" .. prefix .. suffix .. "Storage"
    local totalMethod = "getTotal" .. prefix .. suffix .. "Storage"
    local availMethod = "getAvailable" .. prefix .. suffix .. "Storage"

    -- Check if methods exist
    if not self.bridge[totalMethod] then
        return nil  -- Storage type not supported
    end

    return {
        used = (self.bridge[usedMethod] and self.bridge[usedMethod]()) or 0,
        total = (self.bridge[totalMethod] and self.bridge[totalMethod]()) or 0,
        available = (self.bridge[availMethod] and self.bridge[availMethod]()) or 0
    }
end

return AEInterface
