-- Registry.lua
-- View catalog with metadata

local Manager = mpm('shelfos/view/Manager')

local Registry = {}

-- View categories
Registry.Category = {
    STORAGE = "storage",
    ENERGY = "energy",
    MACHINES = "machines",
    ENVIRONMENT = "environment",
    ALERTS = "alerts",
    OTHER = "other"
}

-- View metadata (extend as views are added)
local viewMeta = {
    InventoryDisplay = {
        category = Registry.Category.STORAGE,
        description = "AE2 network items with change indicators",
        icon = "I"
    },
    InventoryChangesDisplay = {
        category = Registry.Category.STORAGE,
        description = "Accumulated inventory changes over time",
        icon = "C"
    },
    StorageCapacityDisplay = {
        category = Registry.Category.STORAGE,
        description = "AE2 storage capacity graph",
        icon = "S"
    },
    ChestDisplay = {
        category = Registry.Category.STORAGE,
        description = "Connected chest contents",
        icon = "B"
    },
    FluidMonitor = {
        category = Registry.Category.STORAGE,
        description = "AE2 fluid storage",
        icon = "F"
    },
    EnergyStatusDisplay = {
        category = Registry.Category.ENERGY,
        description = "AE2 network energy status",
        icon = "E"
    },
    MachineActivityDisplay = {
        category = Registry.Category.MACHINES,
        description = "Machine busy/idle status grid",
        icon = "M"
    },
    CraftingQueueDisplay = {
        category = Registry.Category.MACHINES,
        description = "AE2 crafting CPUs status",
        icon = "Q"
    },
    WeatherClock = {
        category = Registry.Category.ENVIRONMENT,
        description = "Time, weather, moon phase",
        icon = "W"
    },
    LowStockAlert = {
        category = Registry.Category.ALERTS,
        description = "Items below threshold",
        icon = "!"
    }
}

-- Get metadata for a view
function Registry.getMeta(viewName)
    return viewMeta[viewName] or {
        category = Registry.Category.OTHER,
        description = viewName,
        icon = "?"
    }
end

-- Get all views in a category
function Registry.getByCategory(category)
    local views = Manager.getAvailableViews()
    local filtered = {}

    for _, name in ipairs(views) do
        local meta = Registry.getMeta(name)
        if meta.category == category then
            table.insert(filtered, name)
        end
    end

    return filtered
end

-- Get all categories with their views
function Registry.getCategorized()
    local views = Manager.getAvailableViews()
    local categories = {}

    for _, name in ipairs(views) do
        local meta = Registry.getMeta(name)
        local cat = meta.category

        if not categories[cat] then
            categories[cat] = {}
        end

        table.insert(categories[cat], {
            name = name,
            meta = meta
        })
    end

    return categories
end

-- Search views by name or description
function Registry.search(query)
    local views = Manager.getAvailableViews()
    local results = {}
    local pattern = query:lower()

    for _, name in ipairs(views) do
        local meta = Registry.getMeta(name)
        local nameMatch = name:lower():find(pattern)
        local descMatch = meta.description:lower():find(pattern)

        if nameMatch or descMatch then
            table.insert(results, {
                name = name,
                meta = meta
            })
        end
    end

    return results
end

-- Get full info for a view
function Registry.getFullInfo(viewName)
    local info = Manager.getViewInfo(viewName)
    if not info then
        return nil
    end

    local meta = Registry.getMeta(viewName)

    return {
        name = viewName,
        category = meta.category,
        description = meta.description,
        icon = meta.icon,
        sleepTime = info.sleepTime,
        hasConfig = info.hasConfig,
        configSchema = info.configSchema,
        canMount = Manager.canMount(viewName)
    }
end

-- Register custom view metadata
function Registry.register(viewName, meta)
    viewMeta[viewName] = meta
end

return Registry
