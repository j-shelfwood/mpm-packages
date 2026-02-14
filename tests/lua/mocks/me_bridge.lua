-- Mock ME Bridge Peripheral
-- Simulates Advanced Peripherals ME Bridge for testing

local MEBridge = {}
MEBridge.__index = MEBridge

-- Sample item data
local DEFAULT_ITEMS = {
    {
        name = "minecraft:diamond",
        displayName = "Diamond",
        amount = 256,
        isCraftable = true,
        fingerprint = "diamond_fp_001"
    },
    {
        name = "minecraft:iron_ingot",
        displayName = "Iron Ingot",
        amount = 1024,
        isCraftable = true,
        fingerprint = "iron_fp_001"
    },
    {
        name = "minecraft:gold_ingot",
        displayName = "Gold Ingot",
        amount = 512,
        isCraftable = false,
        fingerprint = "gold_fp_001"
    },
    {
        name = "minecraft:redstone",
        displayName = "Redstone Dust",
        amount = 4096,
        isCraftable = false,
        fingerprint = "redstone_fp_001"
    },
    {
        name = "minecraft:coal",
        displayName = "Coal",
        amount = 2048,
        isCraftable = false,
        fingerprint = "coal_fp_001"
    }
}

local DEFAULT_FLUIDS = {
    {
        name = "minecraft:water",
        displayName = "Water",
        amount = 64000,
        isCraftable = false
    },
    {
        name = "minecraft:lava",
        displayName = "Lava",
        amount = 16000,
        isCraftable = false
    }
}

local DEFAULT_CPUS = {
    {
        name = "Main CPU",
        storage = 16384,
        coProcessors = 4,
        isBusy = false
    },
    {
        name = "Crafting CPU 2",
        storage = 8192,
        coProcessors = 2,
        isBusy = true
    }
}

function MEBridge.new(config)
    config = config or {}
    local self = setmetatable({}, MEBridge)

    self.connected = config.connected ~= false
    self.online = config.online ~= false
    self.items = config.items or DEFAULT_ITEMS
    self.fluids = config.fluids or DEFAULT_FLUIDS
    self.chemicals = config.chemicals or {}
    self.cpus = config.cpus or DEFAULT_CPUS
    self.craftingTasks = config.craftingTasks or {}

    -- Storage stats (in bytes)
    self.itemStorage = {
        total = config.totalItemStorage or 1048576,
        used = config.usedItemStorage or 262144
    }
    self.fluidStorage = {
        total = config.totalFluidStorage or 524288,
        used = config.usedFluidStorage or 131072
    }
    self.chemicalStorage = {
        total = config.totalChemicalStorage or 262144,
        used = config.usedChemicalStorage or 0
    }

    -- Energy stats (AE units)
    self.energy = {
        stored = config.storedEnergy or 500000,
        capacity = config.energyCapacity or 1000000,
        usage = config.energyUsage or 125.5,
        input = config.energyInput or 200.0
    }

    -- Action logs for testing
    self.craftLog = {}
    self.importLog = {}
    self.exportLog = {}

    return self
end

-- Connection status
function MEBridge:isConnected()
    return self.connected
end

function MEBridge:isOnline()
    return self.online
end

-- Item operations
function MEBridge:getItem(filter)
    if not filter or not filter.name then
        return nil, "EMPTY_FILTER"
    end
    for _, item in ipairs(self.items) do
        if item.name == filter.name then
            return {
                name = item.name,
                displayName = item.displayName,
                amount = item.amount,
                isCraftable = item.isCraftable,
                fingerprint = item.fingerprint,
                nbt = item.nbt or {}
            }
        end
    end
    return nil, "Item not found"
end

function MEBridge:getItems(filter)
    if filter and filter.name then
        local result = {}
        for _, item in ipairs(self.items) do
            if item.name:find(filter.name, 1, true) then
                table.insert(result, item)
            end
        end
        return result
    end
    return self.items
end

function MEBridge:getCraftableItems(filter)
    local result = {}
    for _, item in ipairs(self.items) do
        if item.isCraftable then
            if not filter or not filter.name or item.name:find(filter.name, 1, true) then
                table.insert(result, item)
            end
        end
    end
    return result
end

function MEBridge:importItem(filter, direction)
    if not filter or not filter.name then
        return 0, "EMPTY_FILTER"
    end
    local count = filter.count or 64
    table.insert(self.importLog, {
        filter = filter,
        direction = direction,
        count = count
    })
    return count
end

function MEBridge:exportItem(filter, direction)
    if not filter or not filter.name then
        return 0, "EMPTY_FILTER"
    end
    local count = filter.count or 64
    table.insert(self.exportLog, {
        filter = filter,
        direction = direction,
        count = count
    })
    return count
end

-- Fluid operations
function MEBridge:getFluid(filter)
    if not filter or not filter.name then
        return nil, "EMPTY_FILTER"
    end
    for _, fluid in ipairs(self.fluids) do
        if fluid.name == filter.name then
            return fluid
        end
    end
    return nil, "Fluid not found"
end

function MEBridge:getFluids(filter)
    if filter and filter.name then
        local result = {}
        for _, fluid in ipairs(self.fluids) do
            if fluid.name:find(filter.name, 1, true) then
                table.insert(result, fluid)
            end
        end
        return result
    end
    return self.fluids
end

function MEBridge:getCraftableFluids(filter)
    local result = {}
    for _, fluid in ipairs(self.fluids) do
        if fluid.isCraftable then
            table.insert(result, fluid)
        end
    end
    return result
end

function MEBridge:importFluid(filter, direction)
    local count = filter and filter.count or 1000
    return count
end

function MEBridge:exportFluid(filter, direction)
    local count = filter and filter.count or 1000
    return count
end

-- Chemical operations (Mekanism)
function MEBridge:getChemical(filter)
    if not filter or not filter.name then
        return nil, "EMPTY_FILTER"
    end
    for _, chem in ipairs(self.chemicals) do
        if chem.name == filter.name then
            return chem
        end
    end
    return nil, "Chemical not found"
end

function MEBridge:getChemicals(filter)
    return self.chemicals
end

function MEBridge:getCraftableChemicals(filter)
    local result = {}
    for _, chem in ipairs(self.chemicals) do
        if chem.isCraftable then
            table.insert(result, chem)
        end
    end
    return result
end

function MEBridge:importChemical(filter, direction)
    return filter and filter.count or 1000
end

function MEBridge:exportChemical(filter, direction)
    return filter and filter.count or 1000
end

-- Crafting operations
function MEBridge:craftItem(filter, cpuName)
    if not filter or not filter.name then
        return nil, "EMPTY_FILTER"
    end

    -- Check if craftable
    local craftable = false
    for _, item in ipairs(self.items) do
        if item.name == filter.name and item.isCraftable then
            craftable = true
            break
        end
    end

    if not craftable then
        return nil, "NOT_CRAFTABLE"
    end

    local job = {
        id = #self.craftLog + 1,
        status = "crafting",
        item = filter.name,
        count = filter.count or 1
    }

    table.insert(self.craftLog, job)
    table.insert(self.craftingTasks, job)

    return job
end

function MEBridge:craftFluid(filter, cpuName)
    return self:craftItem(filter, cpuName)
end

function MEBridge:craftChemical(filter, cpuName)
    return self:craftItem(filter, cpuName)
end

function MEBridge:isCraftable(filter)
    if not filter or not filter.name then
        return false
    end
    for _, item in ipairs(self.items) do
        if item.name == filter.name and item.isCraftable then
            return true
        end
    end
    return false
end

function MEBridge:isCrafting(filter, cpuName)
    for _, task in ipairs(self.craftingTasks) do
        if task.item == filter.name and task.status == "crafting" then
            return true
        end
    end
    return false
end

function MEBridge:getCraftingCPUs()
    return self.cpus
end

function MEBridge:getCraftingTasks()
    return self.craftingTasks
end

function MEBridge:getCraftingTask(id)
    for _, task in ipairs(self.craftingTasks) do
        if task.id == id then
            return task
        end
    end
    return nil
end

function MEBridge:cancelCraftingTasks(filter)
    local cancelled = 0
    for i = #self.craftingTasks, 1, -1 do
        local task = self.craftingTasks[i]
        if not filter or not filter.name or task.item == filter.name then
            task.status = "cancelled"
            cancelled = cancelled + 1
        end
    end
    return cancelled
end

-- Pattern operations
function MEBridge:getPatterns(filter)
    -- Return sample patterns
    return {
        {
            inputs = {{name = "minecraft:coal", count = 9}},
            outputs = {{name = "minecraft:coal_block", count = 1}}
        },
        {
            inputs = {{name = "minecraft:iron_ingot", count = 9}},
            outputs = {{name = "minecraft:iron_block", count = 1}}
        }
    }
end

-- Energy operations
function MEBridge:getStoredEnergy()
    return self.energy.stored
end

function MEBridge:getEnergyCapacity()
    return self.energy.capacity
end

function MEBridge:getEnergyUsage()
    return self.energy.usage
end

function MEBridge:getAverageEnergyInput()
    return self.energy.input
end

-- Storage statistics
function MEBridge:getTotalItemStorage()
    return self.itemStorage.total
end

function MEBridge:getUsedItemStorage()
    return self.itemStorage.used
end

function MEBridge:getAvailableItemStorage()
    return self.itemStorage.total - self.itemStorage.used
end

function MEBridge:getTotalFluidStorage()
    return self.fluidStorage.total
end

function MEBridge:getUsedFluidStorage()
    return self.fluidStorage.used
end

function MEBridge:getAvailableFluidStorage()
    return self.fluidStorage.total - self.fluidStorage.used
end

function MEBridge:getTotalChemicalStorage()
    return self.chemicalStorage.total
end

function MEBridge:getUsedChemicalStorage()
    return self.chemicalStorage.used
end

function MEBridge:getAvailableChemicalStorage()
    return self.chemicalStorage.total - self.chemicalStorage.used
end

-- External storage (stub - returns 0)
function MEBridge:getTotalExternalItemStorage() return 0 end
function MEBridge:getUsedExternalItemStorage() return 0 end
function MEBridge:getAvailableExternalItemStorage() return 0 end
function MEBridge:getTotalExternalFluidStorage() return 0 end
function MEBridge:getUsedExternalFluidStorage() return 0 end
function MEBridge:getAvailableExternalFluidStorage() return 0 end
function MEBridge:getTotalExternalChemicalStorage() return 0 end
function MEBridge:getUsedExternalChemicalStorage() return 0 end
function MEBridge:getAvailableExternalChemicalStorage() return 0 end

-- Hardware info
function MEBridge:getCells()
    return {
        {
            name = "Storage Cell - 64k",
            totalBytes = 65536,
            usedBytes = 32768,
            totalTypes = 63,
            usedTypes = 15
        }
    }
end

function MEBridge:getDrives()
    return {
        {
            name = "ME Drive",
            cells = 10
        }
    }
end

-- Test helpers
function MEBridge:setItems(items)
    self.items = items
end

function MEBridge:addItem(item)
    table.insert(self.items, item)
end

function MEBridge:getCraftLog()
    return self.craftLog
end

function MEBridge:getImportLog()
    return self.importLog
end

function MEBridge:getExportLog()
    return self.exportLog
end

return MEBridge
