-- MekMultiblockStatus.lua
-- Mekanism multiblock status display (Boiler, Turbine, Fission, Fusion, etc.)

local BaseView = mpm('views/BaseView')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Text = mpm('utils/Text')
local Yield = mpm('utils/Yield')
local MekSnapshotBus = mpm('peripherals/MekSnapshotBus')

-- Get multiblock type options
local function getMultiblockOptions()
    return MekSnapshotBus.getMultiblockOptions()
end

return BaseView.custom({
    sleepTime = 1,

    configSchema = {
        {
            key = "multiblock_type",
            type = "select",
            label = "Multiblock Type",
            options = getMultiblockOptions,
            default = "all"
        }
    },

    mount = function()
        return #MekSnapshotBus.getMultiblockOptions() > 0
    end,

    init = function(self, config)
        self.filterType = config.multiblock_type or "all"
    end,

    getData = function(self)
        local multiblocks = MekSnapshotBus.getMultiblocks(self.filterType)
        local data = { multiblocks = {} }

        for idx, mb in ipairs(multiblocks) do
            table.insert(data.multiblocks, {
                name = mb.name:match("_(%d+)$") or tostring(idx),
                type = mb.type,
                label = mb.label,
                color = mb.color,
                isFormed = mb.isFormed,
                status = mb.status or { active = false, primary = "NOT FORMED", bars = {} }
            })
            Yield.check(idx, 3)
        end

        return data
    end,

    render = function(self, data)
        local multiblocks = data.multiblocks

        if #multiblocks == 0 then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2), "No multiblocks found", colors.orange)
            return
        end

        -- Title
        MonitorHelpers.writeCentered(self.monitor, 1, "Multiblock Status", colors.white)

        -- Calculate layout - each multiblock gets a card
        local cardWidth = math.max(12, math.floor((self.width - 1) / math.min(#multiblocks, 3)))
        local cardHeight = 6
        local cols = math.floor(self.width / cardWidth)
        if cols < 1 then cols = 1 end

        local startY = 3
        local activeCount = 0
        local formedCount = 0

        for idx, mb in ipairs(multiblocks) do
            local col = (idx - 1) % cols
            local row = math.floor((idx - 1) / cols)
            local x = col * cardWidth + 1
            local y = startY + row * (cardHeight + 1)

            if y + cardHeight > self.height then break end

            local status = mb.status

            -- Card background
            local bgColor = colors.black
            if not mb.isFormed then
                bgColor = colors.red
            elseif status.warning then
                bgColor = colors.orange
            elseif status.active then
                bgColor = colors.green
            else
                bgColor = colors.gray
            end

            -- Draw card border/header
            self.monitor.setBackgroundColor(mb.color)
            self.monitor.setCursorPos(x, y)
            self.monitor.write(string.rep(" ", cardWidth - 1))
            self.monitor.setTextColor(colors.black)
            local headerText = mb.label:sub(1, cardWidth - 3)
            self.monitor.setCursorPos(x + 1, y)
            self.monitor.write(headerText)

            -- Card body
            self.monitor.setBackgroundColor(bgColor)
            for i = 1, cardHeight - 1 do
                self.monitor.setCursorPos(x, y + i)
                self.monitor.write(string.rep(" ", cardWidth - 1))
            end

            -- Primary status
            self.monitor.setTextColor(colors.white)
            self.monitor.setCursorPos(x + 1, y + 1)
            self.monitor.write((status.primary or ""):sub(1, cardWidth - 3))

            -- Secondary status
            self.monitor.setTextColor(colors.lightGray)
            self.monitor.setCursorPos(x + 1, y + 2)
            self.monitor.write((status.secondary or ""):sub(1, cardWidth - 3))

            -- Progress bars
            if status.bars then
                for barIdx, bar in ipairs(status.bars) do
                    if barIdx > 2 then break end  -- Max 2 bars
                    local barY = y + 2 + barIdx
                    local barWidth = cardWidth - 4
                    local filledWidth = math.floor((bar.pct or 0) * barWidth)

                    self.monitor.setCursorPos(x + 1, barY)
                    self.monitor.setBackgroundColor(colors.gray)
                    self.monitor.write(string.rep(" ", barWidth))
                    self.monitor.setCursorPos(x + 1, barY)
                    self.monitor.setBackgroundColor(bar.color or colors.green)
                    self.monitor.write(string.rep(" ", filledWidth))

                    -- Bar label
                    self.monitor.setBackgroundColor(bgColor)
                    self.monitor.setTextColor(colors.lightGray)
                    self.monitor.setCursorPos(x + barWidth + 2, barY)
                    self.monitor.write(bar.label:sub(1, 2))
                end
            end

            if status.active then activeCount = activeCount + 1 end
            if mb.isFormed then formedCount = formedCount + 1 end
        end

        -- Status bar
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.gray)
        self.monitor.setCursorPos(1, self.height)
        self.monitor.write(string.format("%d/%d active | %d/%d formed",
            activeCount, #multiblocks, formedCount, #multiblocks))
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Multiblock Status", colors.purple)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "No multiblocks found", colors.gray)
    end
})
