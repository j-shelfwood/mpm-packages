-- AEInterface.lua
-- Unified adapter for AE2 peripherals (me_bridge from Advanced Peripherals, merequester:requester)
-- Normalizes API differences between peripheral types

local module

-- Supported peripheral types in priority order
local PERIPHERAL_TYPES = {
    "me_bridge",           -- Advanced Peripherals ME Bridge
    "merequester:requester" -- ME Requester
}

-- Detect which AE2 peripheral is available
local function findAEPeripheral()
    for _, pType in ipairs(PERIPHERAL_TYPES) do
        local p = peripheral.find(pType)
        if p then
            return p, pType
        end
    end
    return nil, nil
end

-- Check if any supported AE2 peripheral exists
local function hasAEPeripheral()
    for _, pType in ipairs(PERIPHERAL_TYPES) do
        local names = peripheral.getNames()
        for _, name in ipairs(names) do
            if peripheral.getType(name) == pType then
                return true, pType
            end
        end
    end
    return false, nil
end

module = {
    -- Supported peripheral types (exported for views to use)
    PERIPHERAL_TYPES = PERIPHERAL_TYPES,

    -- Find any available AE2 peripheral
    find = findAEPeripheral,

    -- Check if AE2 peripheral exists
    exists = hasAEPeripheral,

    -- Create new AEInterface instance
    -- @param peripheral - Optional: specific peripheral to wrap. If nil, auto-detects.
    new = function(p)
        local detectedType = nil

        if not p then
            p, detectedType = findAEPeripheral()
        else
            -- Determine type of provided peripheral
            for _, pType in ipairs(PERIPHERAL_TYPES) do
                if peripheral.hasType and peripheral.hasType(peripheral.getName(p), pType) then
                    detectedType = pType
                    break
                end
            end
            -- Fallback: try to detect by available methods
            if not detectedType then
                if p.getItems then
                    detectedType = "me_bridge"
                elseif p.items then
                    detectedType = "merequester:requester"
                end
            end
        end

        if not p then
            error("No AE2 peripheral found. Supported types: me_bridge, merequester:requester")
        end

        local self = {
            interface = p,
            peripheralType = detectedType or "unknown"
        }

        return self
    end,

    -- Get peripheral type
    getType = function(self)
        return self.peripheralType
    end,

    -- Fetch all items from the network
    -- Normalizes field names: ensures 'count' field exists
    items = function(self)
        local allItems

        -- Call appropriate method based on peripheral type
        if self.peripheralType == "me_bridge" then
            allItems = self.interface.getItems()
        else
            allItems = self.interface.items()
        end

        if not allItems then
            error("No items detected.")
        end

        -- Normalize item structure
        for _, item in ipairs(allItems) do
            item.id = item.name
            -- ME Bridge uses 'amount', ME Requester uses 'count'
            if item.amount and not item.count then
                item.count = item.amount
            end
            -- Use displayName as name for display purposes
            if item.displayName then
                item.name = item.displayName
            end
        end

        -- Consolidate items by id
        local consolidatedItems = {}
        for _, item in ipairs(allItems) do
            local id = item.id
            if consolidatedItems[id] then
                consolidatedItems[id].count = consolidatedItems[id].count + item.count
            else
                consolidatedItems[id] = {
                    id = id,
                    name = item.name,
                    count = item.count,
                    isCraftable = item.isCraftable
                }
            end
        end

        -- Convert to list
        local items = {}
        for _, item in pairs(consolidatedItems) do
            table.insert(items, item)
        end

        print("Items fetched: " .. #items)
        return items
    end,

    -- Calculate item changes between fetches
    changes = function(self, prev_items)
        local curr_items = module.items(self)

        local prev_dict = {}
        for _, item in ipairs(prev_items) do
            prev_dict[item.id] = item.count
        end

        local changes = {}
        for _, item in ipairs(curr_items) do
            local prev_count = prev_dict[item.id]
            if prev_count and prev_count ~= item.count then
                local change = math.abs(item.count - prev_count)
                local operation = item.count > prev_count and "+" or "-"
                table.insert(changes, {
                    id = item.id,
                    name = item.name,
                    count = item.count,
                    change = change,
                    operation = operation
                })
            end
        end

        print("Changes calculated: " .. #changes)
        return changes
    end,

    -- Fetch all fluids from the network
    -- Normalizes field names: ensures 'amount' field exists
    fluids = function(self)
        local allFluids

        -- Call appropriate method based on peripheral type
        if self.peripheralType == "me_bridge" then
            allFluids = self.interface.getFluids() or {}
        else
            allFluids = self.interface.tanks() or {}
        end

        -- Consolidate fluids
        local consolidatedFluids = {}
        for _, fluid in ipairs(allFluids) do
            if fluid and fluid.name then
                if consolidatedFluids[fluid.name] then
                    consolidatedFluids[fluid.name].amount = consolidatedFluids[fluid.name].amount + (fluid.amount or 0)
                else
                    consolidatedFluids[fluid.name] = {
                        name = fluid.name,
                        amount = fluid.amount or 0
                    }
                end
            end
        end

        -- Convert to list
        local fluids = {}
        for _, fluid in pairs(consolidatedFluids) do
            table.insert(fluids, fluid)
        end

        return fluids
    end,

    -- Calculate fluid changes between fetches
    fluid_changes = function(self, prev_fluids)
        local curr_fluids = module.fluids(self)

        local prev_dict = {}
        for _, fluid in ipairs(prev_fluids) do
            prev_dict[fluid.name] = fluid.amount
        end

        local changes = {}
        for _, fluid in ipairs(curr_fluids) do
            local prev_amount = prev_dict[fluid.name]
            if prev_amount and prev_amount ~= fluid.amount then
                local change = math.abs(fluid.amount - prev_amount)
                local operation = fluid.amount > prev_amount and "+" or "-"
                table.insert(changes, {
                    name = fluid.name,
                    amount = fluid.amount,
                    change = change,
                    operation = operation
                })
            end
        end

        return changes
    end,

    -- Get storage status (capacity information)
    storage_status = function(self)
        local cells

        -- Call appropriate method based on peripheral type
        if self.peripheralType == "me_bridge" then
            cells = self.interface.getCells()
        else
            cells = self.interface.listCells()
        end

        local storageStatus = {
            cells = cells or {},
            usedItemStorage = self.interface.getUsedItemStorage() or 0,
            totalItemStorage = self.interface.getTotalItemStorage() or 0,
            availableItemStorage = self.interface.getAvailableItemStorage() or 0
        }

        return storageStatus
    end,

    -- Get storage cells
    cells = function(self)
        if self.peripheralType == "me_bridge" then
            return self.interface.getCells() or {}
        else
            return self.interface.listCells() or {}
        end
    end,

    -- Categorize cells by type
    categorize_cells = function(self)
        local cells = module.cells(self)
        local categorized = {}

        for _, cell in ipairs(cells) do
            local cellType = cell.item:match(".*_(%w+)$") or "Unknown"
            if not categorized[cellType] then
                categorized[cellType] = 0
            end
            categorized[cellType] = categorized[cellType] + 1
        end

        return categorized
    end,

    -- ME Bridge specific: Get energy information
    energy = function(self)
        if self.peripheralType ~= "me_bridge" then
            return nil, "Energy methods only available on me_bridge"
        end

        return {
            stored = self.interface.getStoredEnergy() or 0,
            capacity = self.interface.getEnergyCapacity() or 0,
            usage = self.interface.getEnergyUsage() or 0
        }
    end,

    -- ME Bridge specific: Check if item is craftable
    isCraftable = function(self, filter)
        if self.peripheralType ~= "me_bridge" then
            return false, "Crafting methods only available on me_bridge"
        end

        return self.interface.isCraftable(filter)
    end,

    -- ME Bridge specific: Request item crafting
    craftItem = function(self, filter, cpuName)
        if self.peripheralType ~= "me_bridge" then
            return nil, "Crafting methods only available on me_bridge"
        end

        return self.interface.craftItem(filter, cpuName)
    end,

    -- ME Bridge specific: Get crafting CPUs
    getCraftingCPUs = function(self)
        if self.peripheralType ~= "me_bridge" then
            return {}, "Crafting methods only available on me_bridge"
        end

        return self.interface.getCraftingCPUs() or {}
    end,

    -- ME Bridge specific: Export item to adjacent inventory
    exportItem = function(self, filter, direction)
        if self.peripheralType ~= "me_bridge" then
            return 0, "Export methods only available on me_bridge"
        end

        return self.interface.exportItem(filter, direction)
    end,

    -- ME Bridge specific: Import item from adjacent inventory
    importItem = function(self, filter, direction)
        if self.peripheralType ~= "me_bridge" then
            return 0, "Import methods only available on me_bridge"
        end

        return self.interface.importItem(filter, direction)
    end
}

return module
