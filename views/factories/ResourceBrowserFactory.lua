-- ResourceBrowserFactory.lua
-- Factory for creating interactive resource browser views
-- Supports items, fluids, chemicals, and craftable resources
-- Provides configurable detail overlay with crafting support
--
-- Split module:
--   ResourceDetailOverlay.lua - Resource detail overlay with crafting

local BaseView = mpm('views/BaseView')
local AEViewSupport = mpm('views/AEViewSupport')
local Text = mpm('utils/Text')
local Yield = mpm('utils/Yield')
local ResourceDetailOverlay = mpm('views/factories/ResourceDetailOverlay')
local SchemaFragments = mpm('views/factories/SchemaFragments')
local DataOps = mpm('views/factories/DataOps')

local ResourceBrowserFactory = {}

-- Default configuration
local DEFAULTS = {
    sleepTime = 5,
    unitDivisor = 1,
    unitLabel = "",
    titleColor = colors.lightGray,
    headerColor = colors.cyan,
    amountColor = colors.white,
    highlightColor = colors.lime,
    craftAmounts = {1, 16, 64},
    lowThreshold = 64,
    emptyMessage = "No resources in storage",
    footerText = "Touch for details",
    sortAscending = false,
    craftableSource = false,  -- When true, fetch from craftable list and merge stock
    alwaysCraftable = false,  -- When true, all items show craft button
}

-- Generate craft button labels from amounts
local function generateCraftLabels(amounts, unitDivisor, unitLabel)
    local labels = {}
    for _, amt in ipairs(amounts) do
        local displayAmt = amt / unitDivisor
        if displayAmt == math.floor(displayAmt) then
            displayAmt = math.floor(displayAmt)
        end
        table.insert(labels, tostring(displayAmt) .. unitLabel)
    end
    return labels
end

-- Create a resource browser view
function ResourceBrowserFactory.create(config)
    config = config or {}

    -- Apply defaults
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then
            config[key] = value
        end
    end

    -- Required fields validation
    assert(config.name, "ResourceBrowserFactory: 'name' is required")
    assert(config.dataMethod, "ResourceBrowserFactory: 'dataMethod' is required")
    assert(config.idField, "ResourceBrowserFactory: 'idField' is required")
    assert(config.amountField, "ResourceBrowserFactory: 'amountField' is required")

    -- Generate labels if not provided
    if not config.craftLabels then
        config.craftLabels = generateCraftLabels(
            config.craftAmounts,
            config.unitDivisor,
            config.unitLabel
        )
    end

    -- Default craft function getter
    if not config.getCraftFunction then
        config.getCraftFunction = function(self, resource)
            if not self.interface then return nil end
            if config.craftMethod then
                local method = self.interface[config.craftMethod]
                if method then
                    return function(filter)
                        return method(self.interface, filter)
                    end
                end
                -- Try bridge directly
                if self.interface.bridge and self.interface.bridge[config.craftMethod] then
                    return self.interface.bridge[config.craftMethod]
                end
            end
            return nil
        end
    end

    -- Build config schema
    local baseConfigSchema = {}

    -- Sort options (skip if using custom config schema)
    local sortField = config.amountField == "count" and "count" or "amount"
    if not config.skipDefaultConfig then
        local sortSchema = SchemaFragments.sortByAmountOrName(sortField, true)
        sortSchema.default = config.sortAscending and (sortField .. "_asc") or sortField
        table.insert(baseConfigSchema, sortSchema)
    end

    -- Min filter option (skip if using custom config schema)
    local minSchema, minKey = SchemaFragments.minFilter(config.unitLabel)
    if not config.skipDefaultConfig then
        table.insert(baseConfigSchema, minSchema)
    end

    -- Merge additional config schema
    if config.configSchema then
        for _, item in ipairs(config.configSchema) do
            table.insert(baseConfigSchema, item)
        end
    end

    local eventKeys = { config.dataMethod }
    if config.craftableSource then
        eventKeys = { "craftableItems", "items" }
    end
    local listenEvents, onEvent = AEViewSupport.buildListener(eventKeys)

    return BaseView.interactive({
        sleepTime = config.sleepTime,
        configSchema = baseConfigSchema,
        listenEvents = listenEvents,
        onEvent = onEvent,

        mount = function()
            return AEViewSupport.mount(config.mountCheck)
        end,

        init = function(self, viewConfig)
            AEViewSupport.init(self)
            self.sortBy = viewConfig.sortBy or sortField
            self.minFilter = viewConfig[minKey] or 0
            self.totalCount = 0
            self.totalAmount = 0
            self.dataUnavailable = false

            -- Store any additional config
            for key, value in pairs(viewConfig) do
                if not self[key] then
                    self[key] = value
                end
            end
        end,

        getData = function(self)
            -- Lazy re-init: if interface was nil at init (host not yet discovered),
            -- retry on each render cycle until it succeeds
            if not AEViewSupport.ensureInterface(self) then return nil end

            local resources
            self.dataUnavailable = false

            -- Craftable source mode: fetch craftable list and merge with stock
            if config.craftableSource then
                local craftableItems = self.interface:getCraftableItems()
                if type(craftableItems) == "table" and type(craftableItems._readStatus) == "table" then
                    local state = craftableItems._readStatus.state
                    self.dataUnavailable = (state == "unavailable" or state == "error")
                end
                if not craftableItems then return {} end

                Yield.yield()

                self.totalCount = #craftableItems

                -- Get all items for stock lookup
                local allItems = self.interface:items()
                if type(allItems) == "table" and type(allItems._readStatus) == "table" then
                    local state = allItems._readStatus.state
                    self.dataUnavailable = self.dataUnavailable or (state == "unavailable" or state == "error")
                end
                if not allItems then return {} end

                Yield.yield()

                -- Build stock lookup
                local stockLookup = {}
                for _, item in ipairs(allItems) do
                    if item[config.idField] then
                        stockLookup[item[config.idField]] = item[config.amountField] or 0
                    end
                end

                -- Merge craftable items with stock data
                resources = {}
                for _, craftable in ipairs(craftableItems) do
                    local id = craftable.name or craftable[config.idField]
                    if id then
                        local count = stockLookup[id] or 0
                        table.insert(resources, {
                            [config.idField] = id,
                            displayName = craftable.displayName or id,
                            [config.amountField] = count,
                            isCraftable = true
                        })
                    end
                end
            else
                -- Standard mode: get data using configured method
                local dataFn = self.interface[config.dataMethod]
                if not dataFn then return {} end

                resources = dataFn(self.interface)
                if type(resources) == "table" and type(resources._readStatus) == "table" then
                    local state = resources._readStatus.state
                    self.dataUnavailable = (state == "unavailable" or state == "error")
                end
                if not resources then return {} end

                self.totalCount = #resources

                Yield.yield()

                -- Fetch craftable list if configured
                if config.getCraftableMethod then
                    local craftableMap = {}
                    local craftableOk = pcall(function()
                        local craftable = self.interface.bridge[config.getCraftableMethod]()
                        if craftable then
                            for _, c in ipairs(craftable) do
                                if c.name then
                                    craftableMap[c.name] = true
                                end
                            end
                        end
                    end)

                    -- Mark craftable resources
                    for _, resource in ipairs(resources) do
                        resource.isCraftable = craftableMap[resource[config.idField]] or false
                    end
                end

                -- Mark all as craftable if configured
                if config.alwaysCraftable then
                    for _, resource in ipairs(resources) do
                        resource.isCraftable = true
                    end
                end
            end

            Yield.yield()

            self.totalAmount = DataOps.totalByAmount(resources, config.amountField, config.unitDivisor)

            -- Filter by minimum (if minFilter is set)
            local minRaw = (self.minFilter or 0) * config.unitDivisor
            local filtered = DataOps.filterByMin(resources, config.amountField, minRaw)

            -- Apply custom filter if provided
            if config.filterData then
                filtered = config.filterData(self, filtered)
            end

            Yield.yield()

            DataOps.sortByAmountOrName(filtered, self.sortBy, config.amountField, sortField, config.idField)

            -- Custom transform if provided
            if config.transformData then
                filtered = config.transformData(self, filtered)
            end

            return filtered
        end,

        header = function(self, data)
            -- Use custom header function if provided
            if config.getHeader then
                return config.getHeader(self, data)
            end

            local headerText = config.headerText or config.name:upper() .. "S"
            return {
                text = headerText,
                color = config.headerColor,
                secondary = " (" .. #data .. "/" .. self.totalCount .. (self.dataUnavailable and " | stale/unavail" or "") .. ")",
                secondaryColor = colors.gray
            }
        end,

        formatItem = function(self, resource)
            local rawAmount = resource[config.amountField] or 0
            local displayAmount = rawAmount / config.unitDivisor
            local amountStr = Text.formatNumber(displayAmount, 0)
            if config.unitLabel ~= "" then
                amountStr = amountStr .. config.unitLabel
            end

            local nameColor = colors.white
            local amountColor = config.amountColor

            -- Highlight craftable resources
            if resource.isCraftable then
                nameColor = config.highlightColor
            end

            -- Highlight low amounts
            if displayAmount == 0 then
                amountColor = colors.red
            elseif displayAmount < config.lowThreshold then
                amountColor = colors.orange
            end

            return {
                lines = {
                    resource.displayName or Text.prettifyName(resource[config.idField] or "Unknown"),
                    amountStr
                },
                colors = { nameColor, amountColor },
                touchAction = "detail",
                touchData = resource
            }
        end,

        onItemTouch = function(self, resource, action)
            ResourceDetailOverlay.show(self, resource, config)
        end,

        footer = function(self, data)
            if self.dataUnavailable then
                return {
                    text = "Data stale/unavailable",
                    color = colors.orange
                }
            end
            local footerText = config.footerText
            -- Show total if using units
            if config.unitLabel ~= "" then
                footerText = Text.formatNumber(self.totalAmount, 0) .. config.unitLabel .. " total"
            end
            return {
                text = footerText,
                color = colors.gray
            }
        end,

        emptyMessage = config.emptyMessage
    })
end

return ResourceBrowserFactory
