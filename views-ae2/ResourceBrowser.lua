-- ResourceBrowser.lua
-- Consolidated AE2 resource browser for items, fluids, and chemicals
-- Uses ResourceBrowserFactory for shared implementation

local ResourceBrowserFactory = mpm('views/factories/ResourceBrowserFactory')
local AEInterface = mpm('peripherals/AEInterface')
local _ = AEInterface

local RESOURCE_TYPES = {
    item = {
        name = "Item",
        dataMethod = "items",
        idField = "registryName",
        amountField = "count",
        unitDivisor = 1,
        unitLabel = "",
        titleColor = colors.lightGray,
        headerColor = colors.cyan,
        amountColor = colors.gray,
        highlightColor = colors.lime,
        craftAmounts = {1, 16, 64},
        craftMethod = "craftItem",
        lowThreshold = 64,
        emptyMessage = "No items in storage",
        footerText = "Touch for details"
    },
    fluid = {
        name = "Fluid",
        dataMethod = "fluids",
        idField = "registryName",
        amountField = "amount",
        unitDivisor = 1000,
        unitLabel = "B",
        titleColor = colors.lightBlue,
        headerColor = colors.cyan,
        amountColor = colors.cyan,
        highlightColor = colors.lime,
        craftAmounts = {1000, 10000, 100000},
        craftMethod = "craftFluid",
        getCraftableMethod = "getCraftableFluids",
        lowThreshold = 100,
        amountLabel = "Amount: ",
        emptyMessage = "No fluids in storage"
    },
    chemical = {
        name = "Chemical",
        dataMethod = "chemicals",
        idField = "registryName",
        amountField = "amount",
        unitDivisor = 1000,
        unitLabel = "B",
        titleColor = colors.lightBlue,
        headerColor = colors.lightBlue,
        amountColor = colors.lightBlue,
        highlightColor = colors.lime,
        craftAmounts = {1000, 10000, 100000},
        craftMethod = "craftChemical",
        getCraftableMethod = "getCraftableChemicals",
        lowThreshold = 100,
        amountLabel = "Amount: ",
        emptyMessage = "No chemicals in storage",
        craftUnavailableMessage = "Chemical crafting unavailable",
        mountCheck = function(caps)
            return caps and caps.hasChemical == true
        end
    }
}

local RESOURCE_OPTIONS = {
    { value = "item", label = "Items" },
    { value = "fluid", label = "Fluids" },
    { value = "chemical", label = "Chemicals" }
}

local RESOURCE_VIEWS = {
    item = ResourceBrowserFactory.create(RESOURCE_TYPES.item),
    fluid = ResourceBrowserFactory.create(RESOURCE_TYPES.fluid),
    chemical = ResourceBrowserFactory.create(RESOURCE_TYPES.chemical)
}

local function resolveResourceType(resourceType)
    if RESOURCE_VIEWS[resourceType] then
        return resourceType
    end
    return "item"
end

local function normalizeSort(resourceType, sortBy)
    local sort = sortBy or "amount"
    if resourceType ~= "item" then
        return sort
    end
    if sort == "amount" then return "count" end
    if sort == "amount_asc" then return "count_asc" end
    return sort
end

local function buildDelegateConfig(resourceType, config)
    local cfg = RESOURCE_TYPES[resourceType]
    local delegateConfig = {
        sortBy = normalizeSort(resourceType, config.sortBy)
    }
    if config.minAmount ~= nil then
        if cfg.unitLabel == "B" then
            delegateConfig.minBuckets = config.minAmount
        else
            delegateConfig.minCount = config.minAmount
        end
    end
    return delegateConfig
end

return {
    sleepTime = 5,
    configSchema = {
        {
            key = "resourceType",
            type = "select",
            label = "Resource Type",
            options = RESOURCE_OPTIONS,
            default = "item"
        },
        {
            key = "sortBy",
            type = "select",
            label = "Sort By",
            options = {
                { value = "amount", label = "Amount (High)" },
                { value = "amount_asc", label = "Amount (Low)" },
                { value = "name", label = "Name (A-Z)" }
            },
            default = "amount"
        },
        {
            key = "minAmount",
            type = "number",
            label = "Min Amount",
            default = 0,
            min = 0,
            max = 100000,
            presets = {0, 1, 10, 64, 1000}
        }
    },

    mount = function()
        return RESOURCE_VIEWS.item.mount()
    end,

    new = function(monitor, config, peripheralName)
        config = config or {}
        local resourceType = resolveResourceType(config.resourceType)
        local delegateView = RESOURCE_VIEWS[resourceType]
        local delegateConfig = buildDelegateConfig(resourceType, config)
        local instance = delegateView.new(monitor, delegateConfig, peripheralName)
        instance._delegateView = delegateView
        instance._resourceType = resourceType
        instance.listenEvents = instance.listenEvents or delegateView.listenEvents or {}
        return instance
    end,

    handleTouch = function(self, x, y)
        if self._delegateView.handleTouch then
            return self._delegateView.handleTouch(self, x, y)
        end
        return false
    end,

    getState = function(self)
        if self._delegateView.getState then
            return self._delegateView.getState(self)
        end
        return nil
    end,

    setState = function(self, state)
        if self._delegateView.setState then
            return self._delegateView.setState(self, state)
        end
    end,

    getData = function(self)
        return self._delegateView.getData(self)
    end,

    renderWithData = function(self, data)
        return self._delegateView.renderWithData(self, data)
    end,

    renderError = function(self, errorMsg)
        if self._delegateView.renderError then
            return self._delegateView.renderError(self, errorMsg)
        end
    end
}
