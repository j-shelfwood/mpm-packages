-- StorageBreakdown.lua
-- Displays internal vs external storage breakdown for AE2
-- Shows separate bars for items/fluids with internal/external split

local AEInterface = mpm('peripherals/AEInterface')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

local module

module = {
    sleepTime = 2,

    configSchema = {
        {
            key = "showFluids",
            type = "select",
            label = "Show Fluids",
            options = {
                { value = true, label = "Yes" },
                { value = false, label = "No" }
            },
            default = true
        },
        {
            key = "showExternal",
            type = "select",
            label = "Show External",
            options = {
                { value = true, label = "Yes" },
                { value = false, label = "No" }
            },
            default = true
        }
    },

    new = function(monitor, config)
        config = config or {}
        local width, height = monitor.getSize()

        local self = {
            monitor = monitor,
            width = width,
            height = height,
            showFluids = config.showFluids ~= false,
            showExternal = config.showExternal ~= false,
            interface = nil,
            initialized = false
        }

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
        if not self.initialized then
            self.monitor.clear()
            self.initialized = true
        end

        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)

        if not self.interface then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No ME Bridge", colors.red)
            return
        end

        -- Helper to get storage stats with error handling
        local function getStorageStats(storageType)
            local stats = {
                internal_used = 0,
                internal_total = 0,
                external_used = 0,
                external_total = 0,
                has_external = false
            }

            local prefix = storageType  -- "Item" or "Fluid" passed directly
            
            -- Get internal storage
            local ok, used = pcall(function() 
                return self.interface.bridge["getUsed" .. prefix .. "Storage"]()
            end)
            if ok and used then stats.internal_used = used end
            Yield.yield()

            ok, total = pcall(function()
                return self.interface.bridge["getTotal" .. prefix .. "Storage"]()
            end)
            if ok and total then stats.internal_total = total end
            Yield.yield()

            -- Get external storage if enabled
            if self.showExternal then
                ok, used = pcall(function()
                    return self.interface.bridge["getUsedExternal" .. prefix .. "Storage"]()
                end)
                if ok and used then
                    stats.external_used = used
                    stats.has_external = true
                end
                Yield.yield()

                ok, total = pcall(function()
                    return self.interface.bridge["getTotalExternal" .. prefix .. "Storage"]()
                end)
                if ok and total then
                    stats.external_total = total
                end
                Yield.yield()
            end

            return stats
        end

        -- Helper to get color based on usage percentage
        local function getUsageColor(percent)
            if percent > 90 then return colors.red
            elseif percent > 75 then return colors.orange
            elseif percent > 50 then return colors.yellow
            else return colors.green end
        end

        -- Helper to draw storage section
        local function drawStorageSection(y, label, stats)
            -- Section label
            self.monitor.setTextColor(colors.white)
            MonitorHelpers.writeAt(self.monitor, 1, y, label)
            y = y + 1

            -- Internal storage
            local intPct = stats.internal_total > 0 and (stats.internal_used / stats.internal_total * 100) or 0
            local intColor = getUsageColor(intPct)
            
            self.monitor.setTextColor(colors.lightGray)
            MonitorHelpers.writeAt(self.monitor, 2, y, "Internal:")
            
            local usedStr = Text.formatNumber(stats.internal_used, 1) .. "B"
            local totalStr = Text.formatNumber(stats.internal_total, 1) .. "B"
            local infoStr = usedStr .. " / " .. totalStr
            
            self.monitor.setTextColor(colors.gray)
            MonitorHelpers.writeAt(self.monitor, self.width - #infoStr + 1, y, infoStr)
            y = y + 1

            -- Internal progress bar
            if self.width >= 10 then
                MonitorHelpers.drawProgressBar(self.monitor, 2, y, self.width - 1, intPct, intColor, colors.gray, true)
                y = y + 1
            end

            -- External storage (if exists and enabled)
            if self.showExternal and stats.has_external and stats.external_total > 0 then
                local extPct = (stats.external_used / stats.external_total * 100)
                local extColor = getUsageColor(extPct)
                
                self.monitor.setTextColor(colors.lightGray)
                MonitorHelpers.writeAt(self.monitor, 2, y, "External:")
                
                usedStr = Text.formatNumber(stats.external_used, 1) .. "B"
                totalStr = Text.formatNumber(stats.external_total, 1) .. "B"
                infoStr = usedStr .. " / " .. totalStr
                
                self.monitor.setTextColor(colors.gray)
                MonitorHelpers.writeAt(self.monitor, self.width - #infoStr + 1, y, infoStr)
                y = y + 1

                -- External progress bar
                if self.width >= 10 then
                    MonitorHelpers.drawProgressBar(self.monitor, 2, y, self.width - 1, extPct, extColor, colors.gray, true)
                    y = y + 1
                end
            end

            return y + 1  -- Extra spacing after section
        end

        -- Clear and render
        self.monitor.clear()

        -- Row 1: Title
        local title = "Storage Breakdown"
        MonitorHelpers.writeCentered(self.monitor, 1, Text.truncateMiddle(title, self.width), colors.white)

        local currentY = 3

        -- Items section
        local itemStats = getStorageStats("Item")
        currentY = drawStorageSection(currentY, "Items", itemStats)

        -- Fluids section
        if self.showFluids and currentY < self.height - 4 then
            local fluidStats = getStorageStats("Fluid")
            currentY = drawStorageSection(currentY, "Fluids", fluidStats)
        end

        -- Total summary at bottom if there's room
        if currentY < self.height - 2 then
            local totalUsed = itemStats.internal_used + itemStats.external_used
            local totalCapacity = itemStats.internal_total + itemStats.external_total
            
            if self.showFluids then
                local fluidStats = getStorageStats("Fluid")
                totalUsed = totalUsed + fluidStats.internal_used + fluidStats.external_used
                totalCapacity = totalCapacity + fluidStats.internal_total + fluidStats.external_total
            end

            local totalPct = totalCapacity > 0 and (totalUsed / totalCapacity * 100) or 0
            local totalColor = getUsageColor(totalPct)

            self.monitor.setTextColor(colors.white)
            MonitorHelpers.writeAt(self.monitor, 1, self.height - 2, "Total:")
            
            self.monitor.setTextColor(totalColor)
            local pctStr = string.format("%.1f%%", totalPct)
            MonitorHelpers.writeAt(self.monitor, self.width - #pctStr + 1, self.height - 2, pctStr)

            -- Total progress bar
            if self.width >= 10 then
                MonitorHelpers.drawProgressBar(self.monitor, 1, self.height, self.width, totalPct, totalColor, colors.gray, true)
            end
        end

        self.monitor.setTextColor(colors.white)
    end
}

return module
