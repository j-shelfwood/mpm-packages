-- EnergyStatusRenderers.lua
-- Render modes for EnergyStatus view
-- Compact, detailed, and graph display modes
-- Extracted from EnergyStatus.lua for maintainability

local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')

local EnergyStatusRenderers = {}

-- Format time duration for display
function EnergyStatusRenderers.formatDuration(seconds)
    if not seconds or seconds <= 0 then return nil end

    if seconds >= 3600 then
        local hours = math.floor(seconds / 3600)
        local mins = math.floor((seconds % 3600) / 60)
        return string.format("%dh %dm", hours, mins)
    elseif seconds >= 60 then
        local mins = math.floor(seconds / 60)
        local secs = math.floor(seconds % 60)
        return string.format("%dm %ds", mins, secs)
    else
        return string.format("%ds", math.floor(seconds))
    end
end

-- Get color based on flow state
function EnergyStatusRenderers.getFlowColor(netFlow, warningThreshold)
    if netFlow >= 0 then
        return colors.lime
    elseif math.abs(netFlow) >= warningThreshold then
        return colors.red
    else
        return colors.orange
    end
end

-- Get color based on storage percentage
function EnergyStatusRenderers.getStorageColor(percent)
    if percent <= 20 then
        return colors.red
    elseif percent <= 50 then
        return colors.yellow
    else
        return colors.lime
    end
end

-- Compact mode: minimal footprint for small monitors
function EnergyStatusRenderers.renderCompact(self, data, flowColor, storageColor)
    -- Row 1: Title + percentage
    self.monitor.setTextColor(colors.cyan)
    self.monitor.setCursorPos(1, 1)
    self.monitor.write("ENERGY")

    local pctStr = string.format("%.0f%%", data.percentage)
    self.monitor.setTextColor(storageColor)
    self.monitor.setCursorPos(self.width - #pctStr + 1, 1)
    self.monitor.write(pctStr)

    -- Row 2: Storage bar
    MonitorHelpers.drawProgressBar(self.monitor, 1, 2, self.width, data.percentage, storageColor, colors.gray, true)

    -- Row 3: Net flow
    local netStr
    if data.netFlow >= 0 then
        netStr = "+" .. Text.formatNumber(data.netFlow, 0) .. " AE/t"
    else
        netStr = Text.formatNumber(data.netFlow, 0) .. " AE/t"
    end
    self.monitor.setTextColor(flowColor)
    MonitorHelpers.writeCentered(self.monitor, 3, netStr, flowColor)

    -- Row 4: Time estimate (if room)
    if self.height >= 4 then
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(1, 4)
        if data.timeToFull then
            self.monitor.write("Full: " .. EnergyStatusRenderers.formatDuration(data.timeToFull))
        elseif data.timeToEmpty then
            self.monitor.write("Empty: " .. EnergyStatusRenderers.formatDuration(data.timeToEmpty))
        else
            self.monitor.write("Stable")
        end
    end
end

-- Detailed mode: full information display
function EnergyStatusRenderers.renderDetailed(self, data, flowColor, storageColor)
    local y = 1

    -- Row 1: Title
    self.monitor.setTextColor(colors.cyan)
    self.monitor.setCursorPos(1, y)
    self.monitor.write("ENERGY STATUS")
    y = y + 2

    -- Storage info
    self.monitor.setTextColor(colors.white)
    self.monitor.setCursorPos(1, y)
    self.monitor.write("Stored: ")
    self.monitor.setTextColor(storageColor)
    self.monitor.write(Text.formatNumber(data.stored, 0))
    self.monitor.setTextColor(colors.gray)
    self.monitor.write(" / " .. Text.formatNumber(data.capacity, 0))
    y = y + 1

    -- Storage bar
    MonitorHelpers.drawProgressBar(self.monitor, 1, y, self.width, data.percentage, storageColor, colors.gray, true)
    y = y + 2

    -- Input rate
    self.monitor.setTextColor(colors.lime)
    self.monitor.setCursorPos(1, y)
    self.monitor.write("IN  ")
    self.monitor.setTextColor(colors.white)
    self.monitor.write(Text.formatNumber(data.input, 1) .. " AE/t")
    y = y + 1

    -- Output rate
    self.monitor.setTextColor(colors.red)
    self.monitor.setCursorPos(1, y)
    self.monitor.write("OUT ")
    self.monitor.setTextColor(colors.white)
    self.monitor.write(Text.formatNumber(data.usage, 1) .. " AE/t")
    y = y + 2

    -- Net flow with indicator
    local indicator = data.netFlow >= 0 and "^" or "v"
    local netStr
    if data.netFlow >= 0 then
        netStr = "+" .. Text.formatNumber(data.netFlow, 1)
    else
        netStr = Text.formatNumber(data.netFlow, 1)
    end

    self.monitor.setTextColor(colors.white)
    self.monitor.setCursorPos(1, y)
    self.monitor.write("NET ")
    self.monitor.setTextColor(flowColor)
    self.monitor.write(netStr .. " AE/t " .. indicator)
    y = y + 2

    -- Time estimate
    if self.height >= y then
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(1, y)
        if data.timeToFull then
            self.monitor.write("Full in " .. EnergyStatusRenderers.formatDuration(data.timeToFull))
        elseif data.timeToEmpty then
            self.monitor.write("Empty in " .. EnergyStatusRenderers.formatDuration(data.timeToEmpty))
        else
            self.monitor.write("Stable")
        end
    end

    -- Bottom: warning threshold
    self.monitor.setTextColor(colors.gray)
    self.monitor.setCursorPos(1, self.height)
    self.monitor.write("Warn: " .. self.warningThreshold .. " AE/t")
end

-- Graph mode: with centered balance history
function EnergyStatusRenderers.renderWithGraph(self, data, flowColor, storageColor)
    -- Row 1: Title + percentage
    self.monitor.setTextColor(colors.cyan)
    self.monitor.setCursorPos(1, 1)
    self.monitor.write("ENERGY STATUS")

    local pctStr = string.format("%.1f%%", data.percentage)
    self.monitor.setTextColor(storageColor)
    self.monitor.setCursorPos(self.width - #pctStr + 1, 1)
    self.monitor.write(pctStr)

    -- Row 2: IN/OUT compact
    self.monitor.setTextColor(colors.lime)
    self.monitor.setCursorPos(1, 2)
    self.monitor.write("IN:")
    self.monitor.setTextColor(colors.white)
    self.monitor.write(Text.formatNumber(data.input, 0))

    self.monitor.setTextColor(colors.red)
    local outX = math.floor(self.width / 2)
    self.monitor.setCursorPos(outX, 2)
    self.monitor.write("OUT:")
    self.monitor.setTextColor(colors.white)
    self.monitor.write(Text.formatNumber(data.usage, 0))

    -- Row 3: Net flow
    local netStr
    if data.netFlow >= 0 then
        netStr = "NET: +" .. Text.formatNumber(data.netFlow, 0) .. " AE/t"
    else
        netStr = "NET: " .. Text.formatNumber(data.netFlow, 0) .. " AE/t"
    end
    self.monitor.setTextColor(flowColor)
    self.monitor.setCursorPos(1, 3)
    self.monitor.write(netStr)

    -- Row 4: Storage bar
    MonitorHelpers.drawProgressBar(self.monitor, 1, 4, self.width, data.percentage, storageColor, colors.gray, true)

    -- Graph area (rows 6 to height-1)
    if self.height >= 9 then
        local graphStartY = 6
        local graphEndY = self.height - 1

        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(1, graphStartY)
        self.monitor.write("Balance History:")

        -- Find max absolute value for scaling
        local maxAbsValue = 1
        for _, v in ipairs(self.history) do
            local absV = math.abs(v)
            if absV > maxAbsValue then
                maxAbsValue = absV
            end
        end

        -- Draw centered graph (0 in middle)
        local graphHeight = graphEndY - graphStartY
        local midY = graphStartY + math.floor(graphHeight / 2)

        -- Clear graph area
        self.monitor.setBackgroundColor(colors.black)
        for gy = graphStartY + 1, graphEndY do
            self.monitor.setCursorPos(1, gy)
            self.monitor.write(string.rep(" ", self.width))
        end

        -- Draw zero line
        self.monitor.setBackgroundColor(colors.gray)
        self.monitor.setCursorPos(1, midY)
        self.monitor.write(string.rep(" ", math.min(#self.history, self.width)))

        -- Draw bars
        local warningThreshold = self.warningThreshold
        for i, value in ipairs(self.history) do
            if i <= self.width then
                local barColor = EnergyStatusRenderers.getFlowColor(value, warningThreshold)
                local barHeight = math.floor((math.abs(value) / maxAbsValue) * (graphHeight / 2))

                if barHeight > 0 and value ~= 0 then
                    self.monitor.setBackgroundColor(barColor)

                    if value >= 0 then
                        for dy = 1, math.min(barHeight, midY - graphStartY - 1) do
                            self.monitor.setCursorPos(i, midY - dy)
                            self.monitor.write(" ")
                        end
                    else
                        for dy = 1, math.min(barHeight, graphEndY - midY) do
                            self.monitor.setCursorPos(i, midY + dy)
                            self.monitor.write(" ")
                        end
                    end
                end
            end
        end

        self.monitor.setBackgroundColor(colors.black)
    end

    -- Bottom: time estimate
    self.monitor.setTextColor(colors.gray)
    self.monitor.setCursorPos(1, self.height)
    if data.timeToFull then
        self.monitor.write("Full: " .. EnergyStatusRenderers.formatDuration(data.timeToFull))
    elseif data.timeToEmpty then
        self.monitor.write("Empty: " .. EnergyStatusRenderers.formatDuration(data.timeToEmpty))
    else
        self.monitor.write("Stable")
    end
end

return EnergyStatusRenderers
