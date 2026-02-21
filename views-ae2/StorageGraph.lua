-- StorageGraph.lua
-- Displays AE2 storage capacity as a graph over time
-- Configurable: storage type (items, fluids, both)

local BaseView = mpm('views/BaseView')
local AEViewSupport = mpm('views/AEViewSupport')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

local function isDegradedState(state)
    return state == "stale" or state == "unavailable" or state == "error"
end

local listenEvents, onEvent = AEViewSupport.buildListener({ "itemStorage", "fluidStorage" })

return BaseView.custom({
    sleepTime = 1,
    listenEvents = listenEvents,
    onEvent = onEvent,

    configSchema = {
        {
            key = "storageType",
            type = "select",
            label = "Storage Type",
            options = {
                { value = "items", label = "Items" },
                { value = "fluids", label = "Fluids" },
                { value = "both", label = "Both (Total)" }
            },
            default = "items"
        }
    },

    mount = function()
            return AEViewSupport.mount()
        end,

    init = function(self, config)
        AEViewSupport.init(self)
        self.storageType = config.storageType or "items"
        self.history = {}
        self.maxHistory = self.width
    end,

    getData = function(self)
        -- Lazy re-init: retry if host not yet discovered at init time
        if not AEViewSupport.ensureInterface(self) then return nil end

        -- Get storage data (with yields after peripheral calls)
        local used, total = 0, 0
        local degraded = false

        if self.storageType == "items" or self.storageType == "both" then
            local status = self.interface:itemStorage()
            Yield.yield()
            if status then
                used = used + (status.used or 0)
                total = total + (status.total or 0)
                degraded = degraded or status._unavailable == true
            end
            degraded = degraded or isDegradedState(AEViewSupport.readStatus(self, "itemStorage").state)
        end

        if self.storageType == "fluids" or self.storageType == "both" then
            local status = self.interface:fluidStorage()
            Yield.yield()
            if status then
                used = used + (status.used or 0)
                total = total + (status.total or 0)
                degraded = degraded or status._unavailable == true
            end
            degraded = degraded or isDegradedState(AEViewSupport.readStatus(self, "fluidStorage").state)
        end

        local percentage = total > 0 and (used / total * 100) or 0

        -- Record history
        MonitorHelpers.recordHistory(self.history, percentage, self.maxHistory)

        return {
            used = used,
            total = total,
            percentage = percentage,
            history = self.history,
            degraded = degraded
        }
    end,

    render = function(self, data)
        -- Determine color
        local barColor = colors.green
        if data.percentage > 90 then
            barColor = colors.red
        elseif data.percentage > 75 then
            barColor = colors.orange
        elseif data.percentage > 50 then
            barColor = colors.yellow
        end

        -- Row 1: Title
        local typeLabel = self.storageType == "both" and "Storage" or (self.storageType:gsub("^%l", string.upper))
        local title = "AE2 " .. typeLabel .. " Capacity"
        MonitorHelpers.writeCentered(self.monitor, 1, Text.truncateMiddle(title, self.width), colors.white)

        -- Row 1 right: Current bytes
        local bytesStr = Text.formatNumber(data.used, 1) .. "B"
        self.monitor.setTextColor(colors.lightGray)
        self.monitor.setCursorPos(math.max(1, self.width - #bytesStr + 1), 1)
        self.monitor.write(bytesStr)

        -- Row 2: Percentage and total
        local pctStr = string.format("%.1f%%", data.percentage)
        self.monitor.setTextColor(barColor)
        self.monitor.setCursorPos(1, 2)
        self.monitor.write(pctStr)

        self.monitor.setTextColor(colors.gray)
        self.monitor.write(" / " .. Text.formatNumber(data.total, 1) .. "B")

        -- Row 4: Progress bar
        if self.height >= 5 then
            MonitorHelpers.drawProgressBar(self.monitor, 1, 4, self.width, data.percentage, barColor, colors.gray, true)
        end

        -- History graph (if room)
        if self.height >= 8 then
            local graphStartY = 6
            local graphEndY = self.height - 1

            self.monitor.setTextColor(colors.gray)
            self.monitor.setCursorPos(1, graphStartY)
            self.monitor.write("History:")

            MonitorHelpers.drawHistoryGraph(
                self.monitor,
                self.history,
                1,
                graphStartY + 1,
                graphEndY,
                100,
                function(val)
                    if val > 90 then return colors.red
                    elseif val > 75 then return colors.orange
                    elseif val > 50 then return colors.yellow
                    else return colors.green end
                end
            )
        end

        -- Bottom: 0 label
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(1, self.height)
        if data.degraded then
            self.monitor.write("Data stale/unavailable")
        else
            self.monitor.write("0")
        end

        self.monitor.setTextColor(colors.white)
    end,

    errorMessage = "Error fetching storage"
})
