-- AEInterface.lua
-- Adapter for AE2 ME Bridge peripheral (Advanced Peripherals)
-- Provides normalized API for item/fluid/energy/crafting operations
-- Supports both local and remote peripherals via Peripherals module

local Peripherals = mpm('utils/Peripherals')
local AESnapshotBus = mpm('peripherals/AESnapshotBus')
local hasRenderContext, RenderContext = pcall(mpm, 'net/RenderContext')
local hasDepStatus, DependencyStatus = pcall(mpm, 'net/DependencyStatus')

local function nowMs()
    return os.epoch("utc")
end

local function markDependency(self, snapshot, maxAgeMs)
    if not self or not self.isRemote then return end
    if not hasRenderContext or not hasDepStatus then return end
    if not RenderContext or not DependencyStatus then return end

    local contextKey = RenderContext.get and RenderContext.get() or nil
    if not contextKey then return end

    local depName = self.bridgeName or "me_bridge"
    if not snapshot then
        DependencyStatus.markPending(contextKey, depName)
        return
    end

    local ageMs = snapshot.updatedAt and (nowMs() - snapshot.updatedAt) or 0
    if snapshot.ok == false and snapshot.data == nil then
        DependencyStatus.markError(contextKey, depName, snapshot.error or "snapshot_error")
        return
    end

    if maxAgeMs and ageMs > maxAgeMs then
        DependencyStatus.markPending(contextKey, depName)
        return
    end

    DependencyStatus.markSuccess(contextKey, depName, snapshot.latencyMs or ageMs)
end

local function snapshotData(self, key, maxAgeMs)
    if not AESnapshotBus then return nil end
    local snapshot = AESnapshotBus.get(self.bridge, key)
    markDependency(self, snapshot, maxAgeMs)
    if snapshot then
        return snapshot.data
    end
    return nil
end

local AEInterface = {}
AEInterface.__index = AEInterface

-- Check if ME Bridge peripheral exists (local or remote)
-- @return boolean, peripheral|nil
function AEInterface.exists()
    if not Peripherals or type(Peripherals.find) ~= "function" then
        return false, nil
    end

    local ok, p = pcall(function()
        return Peripherals.find("me_bridge")
    end)
    if not ok then
        return false, nil
    end

    return p ~= nil, p
end

-- Find ME Bridge peripheral (local or remote)
-- @return peripheral|nil
function AEInterface.find()
    return Peripherals.find("me_bridge")
end

-- Create new AEInterface instance
-- @param p Optional: specific peripheral to wrap. If nil, auto-detects.
-- @return AEInterface instance
-- @throws error if no ME Bridge found
function AEInterface.new(p)
    p = p or Peripherals.find("me_bridge")

    if not p then
        error("No ME Bridge found")
    end

    local self = setmetatable({}, AEInterface)
    self.bridge = p
    self.isRemote = type(p) == "table" and p._isRemote == true
    self.bridgeName = Peripherals.getName(p)
    AESnapshotBus.registerBridge(p)
    return self
end

-- Fetch all items from the network
-- @return array of {registryName, displayName, count, isCraftable}
function AEInterface:items()
    local raw = snapshotData(self, "items", 4000)
    if raw == nil then
        if AESnapshotBus.isRunning() and self.isRemote then
            raw = {}
        else
            raw = self.bridge.getItems() or {}
        end
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

    return result
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
    local raw = snapshotData(self, "fluids", 4000)
    if raw == nil then
        if AESnapshotBus.isRunning() and self.isRemote then
            raw = {}
        else
            raw = self.bridge.getFluids() or {}
        end
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

    return result
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
    local snap = snapshotData(self, "itemStorage", 3000)
    if snap ~= nil then
        return snap
    end

    if AESnapshotBus.isRunning() and self.isRemote then
        return { used = 0, total = 0, available = 0 }
    end

    return {
        used = self.bridge.getUsedItemStorage() or 0,
        total = self.bridge.getTotalItemStorage() or 0,
        available = self.bridge.getAvailableItemStorage() or 0
    }
end

-- Get fluid storage capacity
-- @return {used, total, available}
function AEInterface:fluidStorage()
    local snap = snapshotData(self, "fluidStorage", 3000)
    if snap ~= nil then
        return snap
    end

    if AESnapshotBus.isRunning() and self.isRemote then
        return { used = 0, total = 0, available = 0 }
    end

    return {
        used = self.bridge.getUsedFluidStorage() or 0,
        total = self.bridge.getTotalFluidStorage() or 0,
        available = self.bridge.getAvailableFluidStorage() or 0
    }
end

-- Get energy status
-- @return {stored, capacity, usage}
function AEInterface:energy()
    local snap = snapshotData(self, "energy", 2500)
    if snap ~= nil then
        return snap
    end

    if AESnapshotBus.isRunning() and self.isRemote then
        return { stored = 0, capacity = 0, usage = 0 }
    end

    return {
        stored = self.bridge.getStoredEnergy() or 0,
        capacity = self.bridge.getEnergyCapacity() or 0,
        usage = self.bridge.getEnergyUsage() or 0
    }
end

-- Get all crafting CPUs
-- @return array of {name, storage, coProcessors, isBusy}
function AEInterface:getCraftingCPUs()
    local snap = snapshotData(self, "craftingCPUs", 5000)
    if snap ~= nil then
        return snap
    end
    if AESnapshotBus.isRunning() and self.isRemote then
        return {}
    end
    return self.bridge.getCraftingCPUs() or {}
end

-- Get all active crafting tasks
-- @return array of task tables
function AEInterface:getCraftingTasks()
    local snap = snapshotData(self, "craftingTasks", 3500)
    if snap ~= nil then
        return snap
    end
    if AESnapshotBus.isRunning() and self.isRemote then
        return {}
    end
    return self.bridge.getCraftingTasks() or {}
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
    local snap = snapshotData(self, "cells", 9000)
    if snap ~= nil then
        return snap
    end
    if AESnapshotBus.isRunning() and self.isRemote then
        return {}
    end
    return self.bridge.getCells() or {}
end

-- Get ME drives
-- @return array of drive tables
function AEInterface:getDrives()
    local snap = snapshotData(self, "drives", 9000)
    if snap ~= nil then
        return snap
    end
    if AESnapshotBus.isRunning() and self.isRemote then
        return {}
    end
    return self.bridge.getDrives() or {}
end

-- Get crafting patterns
-- @return array of pattern tables
function AEInterface:getPatterns()
    local snap = snapshotData(self, "patterns", 12000)
    if snap ~= nil then
        return snap
    end
    if AESnapshotBus.isRunning() and self.isRemote then
        return {}
    end
    return self.bridge.getPatterns() or {}
end

-- Get craftable items
-- @return array of craftable item tables
function AEInterface:getCraftableItems()
    local snap = snapshotData(self, "craftableItems", 12000)
    if snap ~= nil then
        return snap
    end
    if AESnapshotBus.isRunning() and self.isRemote then
        return {}
    end
    return self.bridge.getCraftableItems() or {}
end

-- Get average energy input
-- @return number AE/t input rate
function AEInterface:getAverageEnergyInput()
    local snap = snapshotData(self, "averageEnergyInput", 4000)
    if snap ~= nil then
        return snap
    end
    if AESnapshotBus.isRunning() and self.isRemote then
        return 0
    end
    return self.bridge.getAverageEnergyInput() or 0
end

-- Get chemicals (requires Applied Mekanistics)
-- @return array of chemical tables, or empty if not supported
function AEInterface:chemicals()
    if not self.bridge.getChemicals then
        return {}
    end

    local raw = snapshotData(self, "chemicals", 5000)
    if raw == nil then
        if AESnapshotBus.isRunning() and self.isRemote then
            raw = {}
        else
            raw = self.bridge.getChemicals() or {}
        end
    end
    local result = {}

    for _, chem in ipairs(raw) do
        table.insert(result, {
            registryName = chem.name,
            displayName = chem.displayName or chem.name,
            amount = chem.count or chem.amount or 0
        })
    end

    return result
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
