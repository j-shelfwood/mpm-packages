-- ListFactory.lua
-- Factory for creating grid-based resource list views
-- Supports items, fluids, and chemicals with configurable display

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')

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
        {
            key = "warningBelow",
            type = "number",
            label = "Warning Below" .. (config.unitLabel ~= "" and " (" .. config.unitLabel .. ")" or ""),
            default = config.warningDefault,
            min = 1,
            max = 100000,
            presets = config.warningPresets
        },
        {
            key = "sortBy",
            type = "select",
            label = "Sort By",
            options = {
                { value = sortField, label = sortField == "count" and "Count" or "Amount" },
                { value = "name", label = "Name" }
            },
            default = sortField
        }
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

    return BaseView.grid({
        sleepTime = config.sleepTime,
        configSchema = baseConfigSchema,
        minCellWidth = config.minCellWidth or 16,

        mount = function()
            if config.mountCheck then
                return config.mountCheck()
            end
            return AEInterface.exists()
        end,

        init = function(self, viewConfig)
            local ok, interface = pcall(AEInterface.new)
            self.interface = ok and interface or nil
            self.warningBelow = viewConfig.warningBelow or config.warningDefault
            self.sortBy = viewConfig.sortBy or sortField
            self.showCraftable = viewConfig.showCraftable or "all"
            self.totalAmount = 0
        end,

        getData = function(self)
            -- Lazy re-init: if interface was nil at init (host not yet discovered),
            -- retry on each render cycle until it succeeds
            if not self.interface then
                local ok, interface = pcall(AEInterface.new)
                self.interface = ok and interface or nil
            end
            if not self.interface then return nil end

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

            -- Sort
            if self.sortBy == sortField or self.sortBy == "amount" or self.sortBy == "count" then
                table.sort(filtered, function(a, b)
                    return (a[config.amountField] or 0) > (b[config.amountField] or 0)
                end)
            elseif self.sortBy == "name" then
                table.sort(filtered, function(a, b)
                    local nameA = a.displayName or a.registryName or ""
                    local nameB = b.displayName or b.registryName or ""
                    return nameA < nameB
                end)
            end

            -- Calculate total
            self.totalAmount = 0
            for _, resource in ipairs(filtered) do
                self.totalAmount = self.totalAmount + ((resource[config.amountField] or 0) / config.unitDivisor)
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
                secondary = " (" .. #data .. " | " .. totalStr .. ")",
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
