-- AEInterface.lua
-- Adapter for AE2 ME Bridge peripheral (Advanced Peripherals)
-- Provides normalized API for item/fluid/energy/crafting operations
-- Supports both local and remote peripherals via Peripherals module

local Peripherals = mpm('utils/Peripherals')

local AEInterface = {}
AEInterface.__index = AEInterface

-- Check if ME Bridge peripheral exists (local or remote)
-- @return boolean, peripheral|nil
function AEInterface.exists()
    local p = Peripherals.find("me_bridge")
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
    return self
end

-- Fetch all items from the network
-- @return array of {registryName, displayName, count, isCraftable}
function AEInterface:items()
    local raw = self.bridge.getItems() or {}

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
    local raw = self.bridge.getFluids() or {}

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
    return {
        used = self.bridge.getUsedItemStorage() or 0,
        total = self.bridge.getTotalItemStorage() or 0,
        available = self.bridge.getAvailableItemStorage() or 0
    }
end

-- Get fluid storage capacity
-- @return {used, total, available}
function AEInterface:fluidStorage()
    return {
        used = self.bridge.getUsedFluidStorage() or 0,
        total = self.bridge.getTotalFluidStorage() or 0,
        available = self.bridge.getAvailableFluidStorage() or 0
    }
end

-- Get energy status
-- @return {stored, capacity, usage}
function AEInterface:energy()
    return {
        stored = self.bridge.getStoredEnergy() or 0,
        capacity = self.bridge.getEnergyCapacity() or 0,
        usage = self.bridge.getEnergyUsage() or 0
    }
end

-- Get all crafting CPUs
-- @return array of {name, storage, coProcessors, isBusy}
function AEInterface:getCraftingCPUs()
    return self.bridge.getCraftingCPUs() or {}
end

-- Get all active crafting tasks
-- @return array of task tables
function AEInterface:getCraftingTasks()
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
    return self.bridge.getCells() or {}
end

-- Get ME drives
-- @return array of drive tables
function AEInterface:getDrives()
    return self.bridge.getDrives() or {}
end

-- Get crafting patterns
-- @return array of pattern tables
function AEInterface:getPatterns()
    return self.bridge.getPatterns() or {}
end

-- Get craftable items
-- @return array of craftable item tables
function AEInterface:getCraftableItems()
    return self.bridge.getCraftableItems() or {}
end

-- Get average energy input
-- @return number AE/t input rate
function AEInterface:getAverageEnergyInput()
    return self.bridge.getAverageEnergyInput() or 0
end

-- Get chemicals (requires Applied Mekanistics)
-- @return array of chemical tables, or empty if not supported
function AEInterface:chemicals()
    if not self.bridge.getChemicals then
        return {}
    end

    local raw = self.bridge.getChemicals() or {}
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
