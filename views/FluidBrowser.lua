-- FluidBrowser.lua
-- Interactive ME network fluid browser with touch details
-- Touch a fluid to see details and craft if available
-- Consistent with ItemBrowser pattern

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local Core = mpm('ui/Core')
local Yield = mpm('utils/Yield')

-- Fluid detail overlay (blocking)
local function showFluidDetail(self, fluid)
    local monitor = self.monitor
    local width, height = monitor.getSize()

    -- Calculate overlay bounds
    local overlayWidth = math.min(width - 2, 30)
    local overlayHeight = math.min(height - 2, 9)
    local x1 = math.floor((width - overlayWidth) / 2) + 1
    local y1 = math.floor((height - overlayHeight) / 2) + 1
    local x2 = x1 + overlayWidth - 1
    local y2 = y1 + overlayHeight - 1

    -- Use stored peripheral name (monitor is a window buffer, not a peripheral)
    local monitorName = self.peripheralName
    local craftAmount = 1000  -- 1 bucket default for fluids
    local statusMessage = nil
    local statusColor = colors.gray

    while true do
        -- Draw background
        monitor.setBackgroundColor(colors.gray)
        for y = y1, y2 do
            monitor.setCursorPos(x1, y)
            monitor.write(string.rep(" ", overlayWidth))
        end

        -- Title bar
        local displayName = fluid.displayName or Text.prettifyName(fluid.registryName or "Unknown")
        monitor.setBackgroundColor(colors.lightBlue)
        monitor.setTextColor(colors.black)
        monitor.setCursorPos(x1, y1)
        monitor.write(string.rep(" ", overlayWidth))
        monitor.setCursorPos(x1 + 1, y1)
        monitor.write(Core.truncate(displayName, overlayWidth - 2))

        -- Content
        monitor.setBackgroundColor(colors.gray)
        local contentY = y1 + 2

        -- Current amount
        local buckets = (fluid.amount or 0) / 1000
        local amountColor = colors.cyan
        if buckets == 0 then
            amountColor = colors.red
        elseif buckets < 100 then
            amountColor = colors.orange
        end

        monitor.setTextColor(colors.white)
        monitor.setCursorPos(x1 + 1, contentY)
        monitor.write("Amount: ")
        monitor.setTextColor(amountColor)
        monitor.write(Text.formatNumber(buckets, 0) .. " B")
        contentY = contentY + 1

        -- Registry name
        if fluid.registryName then
            monitor.setTextColor(colors.lightGray)
            monitor.setCursorPos(x1 + 1, contentY)
            monitor.write(Core.truncate(fluid.registryName, overlayWidth - 2))
            contentY = contentY + 1
        end

        -- Craftable indicator and amount selector
        if fluid.isCraftable then
            contentY = contentY + 1
            monitor.setTextColor(colors.white)
            monitor.setCursorPos(x1 + 1, contentY)
            monitor.write("Craft: ")

            -- Amount buttons (in mB, display as buckets)
            local amounts = {1000, 10000, 100000}  -- 1B, 10B, 100B
            local labels = {"1B", "10B", "100B"}
            local buttonX = x1 + 8
            for i, amt in ipairs(amounts) do
                local label = labels[i]
                if amt == craftAmount then
                    monitor.setBackgroundColor(colors.cyan)
                    monitor.setTextColor(colors.black)
                else
                    monitor.setBackgroundColor(colors.lightGray)
                    monitor.setTextColor(colors.gray)
                end
                monitor.setCursorPos(buttonX, contentY)
                monitor.write(" " .. label .. " ")
                buttonX = buttonX + #label + 3
            end
        end

        -- Status message
        if statusMessage then
            monitor.setBackgroundColor(colors.gray)
            monitor.setTextColor(statusColor)
            monitor.setCursorPos(x1 + 1, y2 - 2)
            monitor.write(Core.truncate(statusMessage, overlayWidth - 2))
        end

        -- Action buttons
        local buttonY = y2 - 1
        monitor.setBackgroundColor(colors.gray)

        -- Craft button (only if craftable)
        if fluid.isCraftable then
            monitor.setTextColor(colors.lime)
            monitor.setCursorPos(x1 + 2, buttonY)
            monitor.write("[Craft]")
        end

        -- Close button
        monitor.setTextColor(colors.red)
        monitor.setCursorPos(x2 - 7, buttonY)
        monitor.write("[Close]")

        Core.resetColors(monitor)

        -- Wait for touch
        local event, side, tx, ty = os.pullEvent("monitor_touch")

        if side == monitorName then
            -- Close button or outside overlay
            if (ty == buttonY and tx >= x2 - 7 and tx <= x2 - 1) or
               tx < x1 or tx > x2 or ty < y1 or ty > y2 then
                return
            end

            -- Craft button
            if fluid.isCraftable and ty == buttonY and tx >= x1 + 2 and tx <= x1 + 8 then
                if self.interface and self.interface.bridge.craftFluid then
                    local ok, result = pcall(function()
                        return self.interface.bridge.craftFluid({name = fluid.registryName, count = craftAmount})
                    end)

                    if ok and result then
                        statusMessage = "Crafting " .. (craftAmount / 1000) .. "B started"
                        statusColor = colors.lime
                    else
                        statusMessage = "Craft failed"
                        statusColor = colors.red
                    end
                else
                    statusMessage = "Fluid crafting unavailable"
                    statusColor = colors.red
                end
            end

            -- Amount selection (if craftable)
            if fluid.isCraftable and ty == contentY then
                local amounts = {1000, 10000, 100000}
                local labels = {"1B", "10B", "100B"}
                buttonX = x1 + 8
                for i, amt in ipairs(amounts) do
                    local label = labels[i]
                    if tx >= buttonX and tx < buttonX + #label + 2 then
                        craftAmount = amt
                        break
                    end
                    buttonX = buttonX + #label + 3
                end
            end
        end
    end
end

return BaseView.interactive({
    sleepTime = 5,

    configSchema = {
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
            key = "minBuckets",
            type = "number",
            label = "Min Buckets",
            default = 0,
            min = 0,
            max = 100000,
            presets = {0, 1, 10, 100, 1000}
        }
    },

    mount = function()
        return AEInterface.exists()
    end,

    init = function(self, config)
        local ok, interface = pcall(AEInterface.new)
        self.interface = ok and interface or nil
        self.sortBy = config.sortBy or "amount"
        self.minBuckets = config.minBuckets or 0
        self.totalFluids = 0
        self.totalBuckets = 0
    end,

    getData = function(self)
        if not self.interface then return nil end

        local fluids = self.interface:fluids()
        if not fluids then return {} end

        -- Check for craftable fluids and merge data
        local craftableFluids = {}
        local craftableOk = pcall(function()
            local craftable = self.interface.bridge.getCraftableFluids()
            if craftable then
                for _, cf in ipairs(craftable) do
                    if cf.name then
                        craftableFluids[cf.name] = true
                    end
                end
            end
        end)

        Yield.yield()

        -- Mark craftable fluids
        for _, fluid in ipairs(fluids) do
            fluid.isCraftable = craftableFluids[fluid.registryName] or false
        end

        self.totalFluids = #fluids

        -- Calculate total buckets
        self.totalBuckets = 0
        for _, fluid in ipairs(fluids) do
            self.totalBuckets = self.totalBuckets + ((fluid.amount or 0) / 1000)
        end

        Yield.yield()

        -- Filter by minimum buckets
        local filtered = {}
        local minMb = self.minBuckets * 1000
        for _, fluid in ipairs(fluids) do
            if (fluid.amount or 0) >= minMb then
                table.insert(filtered, fluid)
            end
        end

        Yield.yield()

        -- Sort
        if self.sortBy == "amount" then
            table.sort(filtered, function(a, b)
                return (a.amount or 0) > (b.amount or 0)
            end)
        elseif self.sortBy == "amount_asc" then
            table.sort(filtered, function(a, b)
                return (a.amount or 0) < (b.amount or 0)
            end)
        elseif self.sortBy == "name" then
            table.sort(filtered, function(a, b)
                local nameA = a.displayName or a.registryName or ""
                local nameB = b.displayName or b.registryName or ""
                return nameA < nameB
            end)
        end

        return filtered
    end,

    header = function(self, data)
        return {
            text = "FLUIDS",
            color = colors.cyan,
            secondary = " (" .. #data .. "/" .. self.totalFluids .. ")",
            secondaryColor = colors.gray
        }
    end,

    formatItem = function(self, fluid)
        local buckets = (fluid.amount or 0) / 1000
        local bucketStr = Text.formatNumber(buckets, 0) .. "B"

        local nameColor = colors.white
        local amountColor = colors.cyan

        -- Highlight craftable fluids
        if fluid.isCraftable then
            nameColor = colors.lime
        end

        -- Highlight low amounts
        if buckets == 0 then
            amountColor = colors.red
        elseif buckets < 100 then
            amountColor = colors.orange
        end

        return {
            lines = {
                fluid.displayName or Text.prettifyName(fluid.registryName or "Unknown"),
                bucketStr
            },
            colors = { nameColor, amountColor },
            touchAction = "detail",
            touchData = fluid
        }
    end,

    onItemTouch = function(self, fluid, action)
        showFluidDetail(self, fluid)
    end,

    footer = function(self, data)
        local totalStr = Text.formatNumber(self.totalBuckets, 0) .. "B total"
        return {
            text = totalStr,
            color = colors.gray
        }
    end,

    emptyMessage = "No fluids in storage"
})
