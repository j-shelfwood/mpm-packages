-- AEInterface.lua
-- Adapter for AE2 ME Bridge peripheral (Advanced Peripherals)
-- Provides normalized API for item/fluid/energy/crafting operations
-- Supports both local and remote peripherals via RemotePeripheral

local AEInterface = {}
AEInterface.__index = AEInterface

-- Get the peripheral finder (local or remote-aware)
local function getPeripheralAPI()
    -- Try to load RemotePeripheral for network support
    local ok, RemotePeripheral = pcall(mpm, 'net/RemotePeripheral')
    if ok and RemotePeripheral and RemotePeripheral.hasClient() then
        return RemotePeripheral
    end
    -- Fall back to standard peripheral API
    return peripheral
end

-- Check if ME Bridge peripheral exists (local or remote)
-- @return boolean, peripheral|nil
function AEInterface.exists()
    local api = getPeripheralAPI()
    local p = api.find("me_bridge")
    return p ~= nil, p
end

-- Find ME Bridge peripheral (local or remote)
-- @return peripheral|nil
function AEInterface.find()
    local api = getPeripheralAPI()
    return api.find("me_bridge")
end

-- Create new AEInterface instance
-- @param p Optional: specific peripheral to wrap. If nil, auto-detects.
-- @return AEInterface instance
-- @throws error if no ME Bridge found
function AEInterface.new(p)
    local api = getPeripheralAPI()
    p = p or api.find("me_bridge")

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
    local byId = {}
    for _, item in ipairs(raw) do
        local id = item.name  -- registry name like "minecraft:diamond"
        if id then
            if byId[id] then
                byId[id].count = byId[id].count + (item.amount or 0)
            else
                byId[id] = {
                    registryName = id,
                    displayName = item.displayName or id,
                    count = item.amount or 0,
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
        count = item.amount or 0,
        isCraftable = item.isCraftable or false
    }
end

-- Fetch all fluids from the network
-- @return array of {registryName, displayName, amount}
function AEInterface:fluids()
    local raw = self.bridge.getFluids() or {}

    -- Consolidate by registry name
    local byId = {}
    for _, fluid in ipairs(raw) do
        local id = fluid.name
        if id then
            if byId[id] then
                byId[id].amount = byId[id].amount + (fluid.amount or 0)
            else
                byId[id] = {
                    registryName = id,
                    displayName = fluid.displayName or id,
                    amount = fluid.amount or 0
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
        amount = fluid.amount or 0
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

return AEInterface
