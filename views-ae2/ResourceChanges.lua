-- ResourceChanges.lua
-- Consolidated AE2 resource changes for items, fluids, and chemicals
-- Uses ChangesFactory for shared implementation

local ChangesFactory = mpm('views/factories/ChangesFactory')
local SchemaFragments = mpm('views/factories/SchemaFragments')
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
        titleColor = colors.white,
        barColor = colors.blue,
        accentColor = colors.cyan,
        defaultMinChange = 1
    },
    fluid = {
        name = "Fluid",
        dataMethod = "fluids",
        idField = "registryName",
        amountField = "amount",
        unitDivisor = 1000,
        unitLabel = "B",
        titleColor = colors.cyan,
        barColor = colors.cyan,
        accentColor = colors.cyan,
        defaultMinChange = 1000
    },
    chemical = {
        name = "Chemical",
        dataMethod = "chemicals",
        idField = "name",
        amountField = "count",
        unitDivisor = 1000,
        unitLabel = "B",
        titleColor = colors.lightBlue,
        barColor = colors.lightBlue,
        accentColor = colors.lightBlue,
        defaultMinChange = 1000,
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
    item = ChangesFactory.create(RESOURCE_TYPES.item),
    fluid = ChangesFactory.create(RESOURCE_TYPES.fluid),
    chemical = ChangesFactory.create(RESOURCE_TYPES.chemical)
}

local function resolveResourceType(resourceType)
    if RESOURCE_VIEWS[resourceType] then
        return resourceType
    end
    return "item"
end

local function normalizeConfig(resourceType, config)
    local normalized = {}
    for k, v in pairs(config or {}) do
        normalized[k] = v
    end
    if normalized.minChange == nil or normalized.minChange == 1 then
        normalized.minChange = RESOURCE_TYPES[resourceType].defaultMinChange
    end
    return normalized
end

local configSchema = {
    {
        key = "resourceType",
        type = "select",
        label = "Resource Type",
        options = RESOURCE_OPTIONS,
        default = "item"
    }
}
for _, entry in ipairs(SchemaFragments.periodSampleMinChange(1, 1)) do
    table.insert(configSchema, entry)
end

return {
    sleepTime = 3,
    configSchema = configSchema,

    mount = function()
        return RESOURCE_VIEWS.item.mount()
    end,

    new = function(monitor, config, peripheralName)
        config = config or {}
        local resourceType = resolveResourceType(config.resourceType)
        local delegateView = RESOURCE_VIEWS[resourceType]
        local delegateConfig = normalizeConfig(resourceType, config)
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
