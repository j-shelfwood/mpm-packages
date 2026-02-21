-- EnergyStatus.lua
-- Consolidated ME network energy flow monitoring
-- Shows input/output rates, net balance, storage level, and time estimates
-- Configurable display mode: compact, detailed, or graph
--
-- Split module:
--   EnergyStatusRenderers.lua - Render modes (compact, detailed, graph)
--
-- Replaces: EnergyBalance.lua, EnergyFlow.lua

local BaseView = mpm('views/BaseView')
local AEViewSupport = mpm('views/AEViewSupport')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Renderers = mpm('views/EnergyStatusRenderers')

local function isDegradedState(state)
    return state == "stale" or state == "unavailable" or state == "error"
end

return BaseView.custom({
    sleepTime = 1,

    configSchema = {
        {
            key = "displayMode",
            type = "select",
            label = "Display Mode",
            options = {
                { value = "detailed", label = "Detailed" },
                { value = "compact", label = "Compact" },
                { value = "graph", label = "With Graph" }
            },
            default = "detailed"
        },
        {
            key = "warningThreshold",
            type = "number",
            label = "Warning Deficit AE/t",
            default = 100,
            min = 1,
            max = 10000,
            presets = {10, 50, 100, 500, 1000}
        }
    },

    mount = function()
            return AEViewSupport.mount()
        end,

    init = function(self, config)
        AEViewSupport.init(self)
        self.displayMode = config.displayMode or "detailed"
        self.warningThreshold = config.warningThreshold or 100

        -- History for graph mode and trend smoothing
        self.history = {}
        self.maxHistory = self.width
        self.trendHistory = {}
        self.maxTrendHistory = 10
    end,

    getData = function(self)
        -- Lazy re-init: retry if host not yet discovered at init time
        if not AEViewSupport.ensureInterface(self) then return nil end

        -- Get energy stats
        local energy = self.interface:energy()
        if not energy then return nil end

        -- Get input rate
        local input = 0
        local inputOk = pcall(function()
            input = self.interface:getAverageEnergyInput() or 0
        end)
        if not inputOk then input = 0 end

        local energyState = AEViewSupport.readStatus(self, "energy").state
        local inputState = AEViewSupport.readStatus(self, "averageEnergyInput").state

        local stored = energy.stored or 0
        local capacity = energy.capacity or 1
        local usage = energy.usage or 0
        local percentage = capacity > 0 and (stored / capacity * 100) or 0

        -- Calculate net flow
        local netFlow = input - usage

        -- Record in trend history for smoothing
        table.insert(self.trendHistory, netFlow)
        if #self.trendHistory > self.maxTrendHistory then
            table.remove(self.trendHistory, 1)
        end

        -- Calculate average for stable estimates
        local avgFlow = 0
        for _, v in ipairs(self.trendHistory) do
            avgFlow = avgFlow + v
        end
        avgFlow = avgFlow / #self.trendHistory

        -- Record in graph history
        if self.displayMode == "graph" then
            MonitorHelpers.recordHistory(self.history, netFlow, self.maxHistory)
        end

        -- Calculate time estimates
        local timeToFull, timeToEmpty = nil, nil
        if avgFlow > 0 then
            local remaining = capacity - stored
            timeToFull = remaining / avgFlow / 20  -- ticks to seconds
        elseif avgFlow < 0 then
            timeToEmpty = stored / math.abs(avgFlow) / 20
        end

        return {
            stored = stored,
            capacity = capacity,
            percentage = percentage,
            input = input,
            usage = usage,
            netFlow = netFlow,
            avgFlow = avgFlow,
            timeToFull = timeToFull,
            timeToEmpty = timeToEmpty,
            history = self.history,
            degraded = energy._unavailable == true
                or isDegradedState(energyState)
                or isDegradedState(inputState)
        }
    end,

    render = function(self, data)
        local flowColor = Renderers.getFlowColor(data.netFlow, self.warningThreshold)
        local storageColor = Renderers.getStorageColor(data.percentage)

        if self.displayMode == "compact" then
            Renderers.renderCompact(self, data, flowColor, storageColor)
        elseif self.displayMode == "graph" then
            Renderers.renderWithGraph(self, data, flowColor, storageColor)
        else
            Renderers.renderDetailed(self, data, flowColor, storageColor)
        end

        if data.degraded then
            self.monitor.setTextColor(colors.orange)
            self.monitor.setCursorPos(1, self.height)
            self.monitor.write("Data stale/unavailable")
            self.monitor.setTextColor(colors.white)
        end
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, 1, "ENERGY STATUS", colors.cyan)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No ME Network", colors.red)
    end,

    emptyMessage = "No ME Network",
    errorMessage = "Energy Status Error"
})
