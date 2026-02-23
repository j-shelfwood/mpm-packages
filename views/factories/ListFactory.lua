-- ListFactory.lua
-- Factory for creating grid-based resource list views
-- Supports items, fluids, and chemicals with configurable display

local BaseView = mpm('views/BaseView')
local AEViewSupport = mpm('views/AEViewSupport')
local Text = mpm('utils/Text')
local SchemaFragments = mpm('views/factories/SchemaFragments')
local DataOps = mpm('views/factories/DataOps')

local ListFactory = {}

-- Default configuration
local DEFAULTS = {
    sleepTime = 2,
    unitDivisor = 1,
    unitLabel = "",
    headerColor = colors.white,
    amountColor = colors.white,
    warningDefault = 64,
    warningPresets = {16, 64, 256, 1000, 10000},
    maxItems = 100,
    emptyMessage = "No resources in network",
    showCraftableIndicator = false,
}

-- Create a resource list view
function ListFactory.create(config)
    config = config or {}

    -- Apply defaults
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then
            config[key] = value
        end
    end

    -- Required fields validation
    assert(config.name, "ListFactory: 'name' is required")
    assert(config.dataMethod, "ListFactory: 'dataMethod' is required")
    assert(config.amountField, "ListFactory: 'amountField' is required")

    -- Build config schema
    local sortField = config.amountField == "count" and "count" or "amount"
    local baseConfigSchema = {
        SchemaFragments.warningBelow(config.warningDefault, config.unitLabel, config.warningPresets),
        SchemaFragments.sortByAmountOrName(sortField, false)
    }

    -- Add craftable filter for items
    if config.showCraftableFilter then
        table.insert(baseConfigSchema, {
            key = "showCraftable",
            type = "select",
            label = "Show Craftable",
            options = {
                { value = "all", label = "All " .. config.name .. "s" },
                { value = "craftable", label = "Craftable Only" },
                { value = "stored", label = "Stored Only" }
            },
            default = "all"
        })
    end

    -- Merge additional config schema
    if config.configSchema then
        for _, item in ipairs(config.configSchema) do
            table.insert(baseConfigSchema, item)
        end
    end

    local listenEvents, onEvent = AEViewSupport.buildListener({ config.dataMethod })

    return BaseView.grid({
        sleepTime = config.sleepTime,
        configSchema = baseConfigSchema,
        minCellWidth = config.minCellWidth or 16,
        listenEvents = listenEvents,
        onEvent = onEvent,

        mount = function()
            return AEViewSupport.mount(config.mountCheck)
        end,

        init = function(self, viewConfig)
            AEViewSupport.init(self)
            self.warningBelow = viewConfig.warningBelow or config.warningDefault
            self.sortBy = viewConfig.sortBy or sortField
            self.showCraftable = viewConfig.showCraftable or "all"
            self.totalAmount = 0
            self.dataUnavailable = false
        end,

        getData = function(self)
            -- Lazy re-init: if interface was nil at init (host not yet discovered),
            -- retry on each render cycle until it succeeds
            if not AEViewSupport.ensureInterface(self) then return nil end

            -- Check for chemical support if needed
            if config.requireChemicalSupport then
                if not self.interface:hasChemicalSupport() then
                    return {}
                end
            end

            -- Get data using configured method
            local dataFn = self.interface[config.dataMethod]
            if not dataFn then return {} end

            local resources = dataFn(self.interface)
            if type(resources) == "table" and type(resources._readStatus) == "table" then
                local state = resources._readStatus.state
                self.dataUnavailable = (state == "unavailable" or state == "error")
            else
                self.dataUnavailable = false
            end
            if not resources then return {} end

            -- Filter based on showCraftable (for items)
            local filtered = resources
            if config.showCraftableFilter then
                filtered = {}
                for _, resource in ipairs(resources) do
                    local include = true
                    if self.showCraftable == "craftable" then
                        include = resource.isCraftable == true
                    elseif self.showCraftable == "stored" then
                        include = (resource[config.amountField] or 0) > 0
                    end

                    if include then
                        table.insert(filtered, resource)
                    end
                end
            end

            DataOps.sortByAmountOrName(filtered, self.sortBy, config.amountField, sortField, "registryName")
            self.totalAmount = DataOps.totalByAmount(filtered, config.amountField, config.unitDivisor)

            -- Viewport slice: only pass visible items to renderWithData.
            -- renderWithData runs with the buffer hidden (no yields allowed),
            -- so it must be O(1) relative to total inventory size.
            local maxItems = math.min(config.maxItems or 100, 100)
            if #filtered > maxItems then
                local sliced = {}
                for i = 1, maxItems do
                    sliced[i] = filtered[i]
                end
                return sliced
            end

            return filtered
        end,

        header = function(self, data)
            local totalStr = Text.formatNumber(self.totalAmount, 0)
            if config.unitLabel ~= "" then
                totalStr = totalStr .. config.unitLabel
            end

            return {
                text = config.name .. "s",
                color = config.headerColor,
                secondary = " (" .. #data .. " | " .. totalStr .. (self.dataUnavailable and " | stale/unavail" or "") .. ")",
                secondaryColor = colors.gray
            }
        end,

        formatItem = function(self, resource)
            local rawAmount = resource[config.amountField] or 0
            local displayAmount = rawAmount / config.unitDivisor

            -- Color code by amount
            local amountColor = config.amountColor
            if displayAmount < self.warningBelow then
                amountColor = colors.red
            elseif displayAmount < self.warningBelow * 2 then
                amountColor = colors.orange
            elseif config.showCraftableIndicator and displayAmount >= self.warningBelow * 10 then
                amountColor = colors.lime
            end

            -- Get display name
            local name = resource.displayName or resource.registryName or "Unknown"
            if name == resource.registryName then
                name = Text.prettifyName(name)
            end

            -- Format amount string
            local amountStr = Text.formatNumber(displayAmount, 0)
            if config.unitLabel ~= "" then
                amountStr = amountStr .. config.unitLabel
            end

            -- Craftable indicator (for items)
            if config.showCraftableIndicator then
                if resource.isCraftable and rawAmount == 0 then
                    amountStr = "[C]"
                    amountColor = colors.cyan
                elseif resource.isCraftable then
                    amountStr = amountStr .. "*"
                end
            end

            return {
                lines = { name, amountStr },
                colors = { colors.white, amountColor }
            }
        end,

        emptyMessage = config.emptyMessage,
        maxItems = config.maxItems
    })
end

return ListFactory
