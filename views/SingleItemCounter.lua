-- SingleItemCounter.lua
-- Displays a single item count with large numbers
-- Configurable: item to monitor, warning threshold

local AEInterface = mpm('peripherals/AEInterface')

local module

-- Prettify item name for display
local function prettifyName(id)
    if not id then return "No Item" end
    local _, _, name = string.find(id, ":(.+)")
    if name then
        name = name:gsub("_", " ")
        return name:gsub("^%l", string.upper)
    end
    return id
end

-- Format count with K/M suffix
local function formatCount(count)
    if not count then return "0" end
    if count >= 1000000 then
        return string.format("%.1fM", count / 1000000)
    elseif count >= 1000 then
        return string.format("%.1fK", count / 1000)
    else
        return tostring(math.floor(count))
    end
end

module = {
    sleepTime = 1,

    -- Configuration schema for this view
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

    new = function(monitor, config)
        config = config or {}
        local width, height = monitor.getSize()

        local self = {
            monitor = monitor,
            width = width,
            height = height,
            itemId = config.item,
            warningBelow = config.warningBelow or 100,
            interface = nil,
            prevCount = nil,
            changeIndicator = "",
            initialized = false
        }

        -- Try to create interface
        local ok, interface = pcall(AEInterface.new)
        if ok and interface then
            self.interface = interface
        end

        return self
    end,

    mount = function()
        return AEInterface.exists()
    end,

    render = function(self)
        -- One-time initialization
        if not self.initialized then
            self.monitor.clear()
            self.initialized = true
        end

        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)

        -- Check interface
        if not self.interface then
            self.monitor.setCursorPos(1, math.floor(self.height / 2))
            self.monitor.write("No AE2 peripheral")
            return
        end

        -- Check if item is configured
        if not self.itemId then
            self.monitor.setCursorPos(1, math.floor(self.height / 2) - 1)
            self.monitor.write("Item Counter")
            self.monitor.setCursorPos(1, math.floor(self.height / 2) + 1)
            self.monitor.write("Configure to select item")
            return
        end

        -- Fetch items
        local ok, items = pcall(AEInterface.items, self.interface)
        if not ok or not items then
            self.monitor.setCursorPos(1, 1)
            self.monitor.setTextColor(colors.red)
            self.monitor.write("Error fetching items")
            return
        end

        -- Find our item
        local count = 0
        local isCraftable = false
        for _, item in ipairs(items) do
            if item.name == self.itemId then
                count = item.count or 0
                isCraftable = item.isCraftable or false
                break
            end
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

        -- Clear screen
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.clear()

        -- Row 1: Item name
        local name = prettifyName(self.itemId)
        if #name > self.width then
            name = name:sub(1, self.width - 3) .. "..."
        end
        self.monitor.setTextColor(colors.white)
        local nameX = math.floor((self.width - #name) / 2) + 1
        self.monitor.setCursorPos(nameX, 1)
        self.monitor.write(name)

        -- Center area: Large count
        local countStr = formatCount(count)
        local centerY = math.floor(self.height / 2)

        self.monitor.setTextColor(countColor)
        local countX = math.floor((self.width - #countStr) / 2) + 1
        self.monitor.setCursorPos(countX, centerY)
        self.monitor.write(countStr)

        -- Change indicator
        if self.changeIndicator ~= "" then
            local indicatorColor = self.changeIndicator == "+" and colors.green or colors.red
            self.monitor.setTextColor(indicatorColor)
            self.monitor.setCursorPos(countX + #countStr + 1, centerY)
            if countX + #countStr + 1 <= self.width then
                self.monitor.write(self.changeIndicator)
            end
        end

        -- Warning/Status row
        local statusY = centerY + 2
        if statusY <= self.height - 1 then
            if isWarning then
                self.monitor.setTextColor(colors.red)
                local warnText = "LOW STOCK!"
                self.monitor.setCursorPos(math.floor((self.width - #warnText) / 2) + 1, statusY)
                self.monitor.write(warnText)
            elseif isCraftable then
                self.monitor.setTextColor(colors.lime)
                local craftText = "[Craftable]"
                self.monitor.setCursorPos(math.floor((self.width - #craftText) / 2) + 1, statusY)
                self.monitor.write(craftText)
            end
        end

        -- Bottom: threshold info
        self.monitor.setTextColor(colors.gray)
        local thresholdStr = "Warn <" .. self.warningBelow
        self.monitor.setCursorPos(1, self.height)
        self.monitor.write(thresholdStr)

        -- Reset colors
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)
    end
}

return module
