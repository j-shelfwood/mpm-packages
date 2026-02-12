-- ItemCounter.lua
-- Displays a single item count with large numbers
-- Configurable: item to monitor, warning threshold

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

return BaseView.custom({
    sleepTime = 1,

    configSchema = {
        {
            key = "item",
            type = "item:id",
            label = "Item",
            default = nil,
            required = true
        },
        {
            key = "warningBelow",
            type = "number",
            label = "Warning Below",
            default = 100,
            min = 0,
            max = 1000000,
            presets = {10, 50, 100, 500, 1000, 10000}
        }
    },

    mount = function()
        return AEInterface.exists()
    end,

    init = function(self, config)
        self.interface = AEInterface.new()
        self.itemId = config.item
        self.warningBelow = config.warningBelow or 100
        self.prevCount = nil
        self.changeIndicator = ""
    end,

    getData = function(self)
        if not self.itemId then
            return nil
        end

        -- Fetch items
        local items = self.interface:items()
        if not items then return nil end

        Yield.yield()

        -- Find our item by registry name (with yields for large systems)
        local count = 0
        local isCraftable = false
        local itemId = self.itemId
        local iterCount = 0
        for _, item in ipairs(items) do
            if item.registryName == itemId then
                count = item.count or 0
                isCraftable = item.isCraftable or false
                break
            end
            iterCount = iterCount + 1
            Yield.check(iterCount)
        end

        -- Track change direction
        if self.prevCount ~= nil then
            if count > self.prevCount then
                self.changeIndicator = "+"
            elseif count < self.prevCount then
                self.changeIndicator = "-"
            else
                self.changeIndicator = ""
            end
        end
        self.prevCount = count

        return {
            count = count,
            isCraftable = isCraftable,
            changeIndicator = self.changeIndicator
        }
    end,

    render = function(self, data)
        local count = data.count

        -- Determine color based on warning threshold
        local countColor = colors.white
        local isWarning = count < self.warningBelow

        if isWarning then
            countColor = colors.red
        elseif count < self.warningBelow * 2 then
            countColor = colors.orange
        elseif count >= self.warningBelow * 10 then
            countColor = colors.lime
        end

        -- Row 1: Item name (prettified from registry name)
        local name = Text.truncateMiddle(Text.prettifyName(self.itemId), self.width)
        MonitorHelpers.writeCentered(self.monitor, 1, name, colors.white)

        -- Center: Large count
        local countStr = Text.formatNumber(count, 0)
        local centerY = math.floor(self.height / 2)
        MonitorHelpers.writeCentered(self.monitor, centerY, countStr, countColor)

        -- Change indicator
        if data.changeIndicator ~= "" then
            local indicatorColor = data.changeIndicator == "+" and colors.green or colors.red
            local countX = math.floor((self.width - #countStr) / 2) + 1
            if countX + #countStr + 1 <= self.width then
                self.monitor.setTextColor(indicatorColor)
                self.monitor.setCursorPos(countX + #countStr + 1, centerY)
                self.monitor.write(data.changeIndicator)
            end
        end

        -- Warning/Status row
        local statusY = centerY + 2
        if statusY <= self.height - 1 then
            if isWarning then
                MonitorHelpers.writeCentered(self.monitor, statusY, "LOW STOCK!", colors.red)
            elseif data.isCraftable then
                MonitorHelpers.writeCentered(self.monitor, statusY, "[Craftable]", colors.lime)
            end
        end

        -- Bottom: threshold info
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(1, self.height)
        self.monitor.write("Warn <" .. self.warningBelow)

        self.monitor.setTextColor(colors.white)
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Item Counter", colors.white)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Configure to select item", colors.gray)
    end,

    errorMessage = "Error fetching items"
})
