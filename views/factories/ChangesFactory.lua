-- ChangesFactory.lua
-- Factory for generating resource change tracking views
-- Creates Item/Fluid/ChemicalChanges with configurable data source
-- Split: ChangesOverlay.lua, ChangesDataHandler.lua, ChangesRenderer.lua

local BaseView = mpm('views/BaseView')
local AEInterface = mpm('peripherals/AEInterface')
local GridDisplay = mpm('utils/GridDisplay')
local Text = mpm('utils/Text')
local ChangesOverlay = mpm('views/factories/ChangesOverlay')
local DataHandler = mpm('views/factories/ChangesDataHandler')
local Renderer = mpm('views/factories/ChangesRenderer')

local ChangesFactory = {}

-- Create a Changes view with the given configuration
-- @param config Table:
--   name: View name for display (e.g., "Item", "Fluid", "Chemical")
--   dataMethod: AEInterface method (e.g., "items", "fluids", "chemicals")
--   idField: Field name for resource ID (e.g., "registryName", "name")
--   amountField: Field name for amount (e.g., "count", "amount")
--   unitDivisor: Divide amounts for display (1 for items, 1000 for fluids/chemicals)
--   unitLabel: Unit suffix (e.g., "", "B")
--   titleColor: Header color
--   barColor: Timer bar color
--   accentColor: Accent color for amounts
--   defaultMinChange: Default minimum change threshold
--   mountCheck: Optional function to check if view can mount
-- @return View definition table
function ChangesFactory.create(config)
    config = config or {}
    config.name = config.name or "Resource"
    config.dataMethod = config.dataMethod or "items"
    config.idField = config.idField or "registryName"
    config.amountField = config.amountField or "count"
    config.unitDivisor = config.unitDivisor or 1
    config.unitLabel = config.unitLabel or ""
    config.titleColor = config.titleColor or colors.white
    config.barColor = config.barColor or colors.blue
    config.accentColor = config.accentColor or colors.cyan
    config.defaultMinChange = config.defaultMinChange or 1

    -- Format function for grid display
    local formatChange = nil  -- Forward declaration
    formatChange = function(self, resource)
        local color = resource.change > 0 and colors.lime or colors.red
        local sign = resource.change > 0 and "+" or ""
        local displayChange = resource.change / config.unitDivisor
        local name = Text.prettifyName(resource.id)
        local changeStr = sign .. Text.formatNumber(displayChange, 1) .. config.unitLabel

        -- Check if compact mode is active
        local compact = self.display and self.display.compact_mode

        if compact then
            -- Single-line format: "Name +123"
            local truncatedName = Text.truncateEnd(name, 10)
            local line = truncatedName .. " " .. changeStr

            -- Build per-character color array
            local colorArray = {}
            for i = 1, #truncatedName do
                colorArray[i] = colors.white
            end
            colorArray[#truncatedName + 1] = colors.gray  -- Space
            for i = #truncatedName + 2, #line do
                colorArray[i] = color
            end

            return {
                lines = { line },
                colors = { colorArray }
            }
        else
            -- Standard 2-line format
            return {
                lines = { name, changeStr },
                colors = { colors.white, color }
            }
        end
    end

    return BaseView.custom({
        sleepTime = 3,

        configSchema = {
            {
                key = "periodSeconds",
                type = "number",
                label = "Reset Period (sec)",
                default = 60,
                min = 10,
                max = 86400,
                presets = {30, 60, 300, 600, 1800}
            },
            {
                key = "showMode",
                type = "select",
                label = "Show Changes",
                options = {
                    { value = "both", label = "Gains & Losses" },
                    { value = "gains", label = "Gains Only" },
                    { value = "losses", label = "Losses Only" }
                },
                default = "both"
            },
            {
                key = "minChange",
                type = "number",
                label = "Min Change",
                default = config.defaultMinChange,
                min = 1,
                max = 100000,
                presets = config.unitDivisor > 1 and {100, 1000, 5000, 10000} or {1, 10, 50, 100}
            }
        },

        mount = function()
            if config.mountCheck then
                return config.mountCheck()
            end
            return AEInterface.exists()
        end,

        init = function(self, viewConfig)
            local ok, interface = pcall(AEInterface.new)
            self.interface = ok and interface or nil

            self.periodSeconds = viewConfig.periodSeconds or 60
            self.showMode = viewConfig.showMode or "both"
            self.minChange = viewConfig.minChange or config.defaultMinChange

            self.display = GridDisplay.new(self.monitor)

            self.state = "init"
            self.baseline = {}
            self.baselineCount = 0
            self.periodStart = 0
            self.cachedData = nil
            self.lastUpdate = 0
            self.lastChanges = {}
            self.factoryConfig = config
        end,

        getData = function(self)
            -- Lazy re-init: if interface was nil at init (host not yet discovered),
            -- retry on each render cycle until it succeeds
            if not self.interface then
                local ok, interface = pcall(AEInterface.new)
                self.interface = ok and interface or nil
            end
            if not self.interface then
                return { error = "No AE2 peripheral" }
            end

            if config.mountCheck and not config.mountCheck() then
                return { error = config.name .. " not available" }
            end

            local now = os.epoch("utc")

            -- State: init
            if self.state == "init" then
                local snapshot, count, ok = DataHandler.takeSnapshot(self.interface, config.dataMethod, config.idField, config.amountField)
                if ok and count > 0 then
                    self.baseline = DataHandler.copySnapshot(snapshot)
                    self.baselineCount = count
                    self.periodStart = now
                    self.state = "baseline_set"
                    self.cachedData = nil
                    self.lastUpdate = 0
                    return {
                        status = "baseline_captured",
                        baselineCount = count,
                        elapsed = 0
                    }
                else
                    return { status = "waiting" }
                end
            end

            if self.state == "baseline_set" then
                self.state = "tracking"
            end

            local elapsed = (now - self.periodStart) / 1000

            -- Period reset
            if elapsed >= self.periodSeconds then
                local snapshot, count, ok = DataHandler.takeSnapshot(self.interface, config.dataMethod, config.idField, config.amountField)
                if ok and count > 0 then
                    self.baseline = DataHandler.copySnapshot(snapshot)
                    self.baselineCount = count
                    self.periodStart = now
                    self.cachedData = nil
                    self.lastUpdate = 0
                    return {
                        status = "period_reset",
                        baselineCount = count,
                        elapsed = 0
                    }
                end
            end

            -- Use cached data
            if self.cachedData and self.lastUpdate >= self.periodStart then
                return {
                    status = "tracking",
                    changes = self.cachedData.changes,
                    totalGains = self.cachedData.totalGains,
                    totalLosses = self.cachedData.totalLosses,
                    baselineCount = self.baselineCount,
                    currentCount = self.cachedData.currentCount,
                    elapsed = elapsed
                }
            end

            -- Take current snapshot
            local current, resourceCount, ok = DataHandler.takeSnapshot(self.interface, config.dataMethod, config.idField, config.amountField)
            if not ok then
                return { error = "Error reading " .. config.name:lower() .. "s" }
            end

            local changes = DataHandler.calculateChanges(self.baseline, current, self.showMode, self.minChange)

            table.sort(changes, function(a, b)
                return math.abs(a.change) > math.abs(b.change)
            end)

            local totalGains, totalLosses = DataHandler.calculateTotals(changes)

            self.cachedData = {
                changes = changes,
                totalGains = totalGains,
                totalLosses = totalLosses,
                currentCount = resourceCount
            }
            self.lastUpdate = now

            return {
                status = "tracking",
                changes = changes,
                totalGains = totalGains,
                totalLosses = totalLosses,
                baselineCount = self.baselineCount,
                currentCount = resourceCount,
                elapsed = elapsed
            }
        end,

        render = function(self, data)
            local cfg = self.factoryConfig

            -- Handle errors
            if data.error then
                Renderer.renderError(self, data, cfg)
                return
            end

            -- Waiting state
            if data.status == "waiting" then
                Renderer.renderWaiting(self, cfg)
                return
            end

            -- Baseline captured
            if data.status == "baseline_captured" then
                Renderer.renderBaselineCaptured(self, data, cfg)
                return
            end

            -- Period reset
            if data.status == "period_reset" then
                Renderer.renderPeriodReset(self, data, cfg)
                return
            end

            -- Tracking state
            local changes = data.changes or {}
            local remaining = math.max(0, math.floor(self.periodSeconds - data.elapsed))

            -- No changes
            if #changes == 0 then
                Renderer.renderNoChanges(self, data, cfg)
                return
            end

            -- Display in grid (bind self for compact mode detection)
            self.display:display(changes, function(item)
                return formatChange(self, item)
            end)

            -- Header and summary
            Renderer.renderHeader(self, data, cfg, remaining)
            Renderer.renderSummary(self, data, cfg)

            DataHandler.drawTimerBar(self.monitor, self.height, self.width, data.elapsed, self.periodSeconds, cfg.barColor)

            self.lastChanges = changes

            self.monitor.setTextColor(colors.white)
        end,

        onTouch = function(self, x, y)
            if #self.lastChanges == 0 then
                return false
            end

            local itemsPerRow = math.floor(self.width / 12)
            if itemsPerRow < 1 then itemsPerRow = 1 end

            local startY = 3
            local itemHeight = 2
            local itemWidth = math.floor(self.width / itemsPerRow)

            if y >= startY and y < self.height then
                local row = math.floor((y - startY) / itemHeight)
                local col = math.floor((x - 1) / itemWidth)
                local index = row * itemsPerRow + col + 1

                if index >= 1 and index <= #self.lastChanges then
                    ChangesOverlay.show(self, self.lastChanges[index], self.factoryConfig)
                    return true
                end
            end

            return false
        end,

        errorMessage = "Error tracking changes"
    })
end

return ChangesFactory
