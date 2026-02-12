-- MachineStatus.lua
-- Displays status of machines of a specific type
-- Shows green when busy, gray when idle

local BaseView = mpm('views/BaseView')
local Text = mpm('utils/Text')
local MonitorHelpers = mpm('utils/MonitorHelpers')
local Yield = mpm('utils/Yield')

-- Get available machine types from connected peripherals
local function getMachineTypes()
    local types = {}
    local seen = {}
    local names = peripheral.getNames()

    for _, name in ipairs(names) do
        local pType = peripheral.getType(name)
        if pType and not seen[pType] then
            local p = peripheral.wrap(name)
            if p and type(p.isBusy) == "function" then
                seen[pType] = true
                local _, _, shortName = string.find(pType, ":(.+)")
                local label = shortName or pType
                label = label:gsub("_", " "):gsub("^%l", string.upper)
                table.insert(types, {
                    value = pType,
                    label = label
                })
            end
        end
    end

    return types
end

return BaseView.custom({
    sleepTime = 1,

    configSchema = {
        {
            key = "machine_type",
            type = "select",
            label = "Machine Type",
            options = getMachineTypes,
            default = nil,
            required = true
        }
    },

    mount = function()
        return true
    end,

    init = function(self, config)
        self.machineType = config.machine_type
        self.peripherals = {}
        self.title = ""

        if self.machineType then
            local _, _, machineTypeName = string.find(self.machineType, ":(.+)")
            machineTypeName = machineTypeName or self.machineType
            machineTypeName = machineTypeName:gsub("_", " ")
            self.title = machineTypeName:gsub("^%l", string.upper)

            local names = peripheral.getNames()
            for _, name in ipairs(names) do
                if peripheral.getType(name) == self.machineType then
                    table.insert(self.peripherals, peripheral.wrap(name))
                end
            end
        end
    end,

    getData = function(self)
        if not self.machineType then
            return nil
        end

        -- Fetch machine data (with yields for many machines)
        local machineData = {}
        local machineType = self.machineType
        for idx, machine in ipairs(self.peripherals) do
            local fullName = peripheral.getName(machine)
            local _, _, shortName = string.find(fullName, machineType .. "_(.+)")
            shortName = shortName or fullName

            local busyOk, isBusy = pcall(machine.isBusy)
            if not busyOk then isBusy = false end

            table.insert(machineData, {
                name = shortName,
                isBusy = isBusy
            })
            Yield.check(idx)
        end

        return machineData
    end,

    render = function(self, data)
        if #data == 0 then
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "No machines found", colors.orange)
            MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, self.machineType, colors.gray)
            return
        end

        -- Calculate grid layout
        local barWidth = 7
        local barHeight = 4
        local columns = math.min(2, #data)
        local rows = math.ceil(#data / columns)

        local totalGridHeight = rows * (barHeight + 1) - 1
        local topMargin = math.max(2, math.floor((self.height - totalGridHeight) / 2))

        -- Draw title
        MonitorHelpers.writeCentered(self.monitor, 1, self.title, colors.white)

        -- Draw machine grid
        for idx, machine in ipairs(data) do
            local column = (idx - 1) % columns
            local row = math.ceil(idx / columns)
            local x = column * (barWidth + 2) + 2
            local y = (row - 1) * (barHeight + 1) + topMargin

            if machine.isBusy then
                self.monitor.setBackgroundColor(colors.green)
            else
                self.monitor.setBackgroundColor(colors.gray)
            end

            for i = 0, barHeight - 1 do
                self.monitor.setCursorPos(x, y + i)
                self.monitor.write(string.rep(" ", barWidth))
            end

            self.monitor.setTextColor(colors.black)
            local nameLen = #(machine.name or "")
            self.monitor.setCursorPos(x + math.floor((barWidth - nameLen) / 2), y + math.floor(barHeight / 2))
            self.monitor.write(machine.name or "?")
        end

        -- Count busy
        local busyCount = 0
        for _, m in ipairs(data) do
            if m.isBusy then busyCount = busyCount + 1 end
        end

        -- Bottom status
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.gray)
        local statusStr = busyCount .. "/" .. #data .. " active"
        self.monitor.setCursorPos(1, self.height)
        self.monitor.write(statusStr)

        self.monitor.setTextColor(colors.white)
    end,

    renderEmpty = function(self)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) - 1, "Machine Status", colors.white)
        MonitorHelpers.writeCentered(self.monitor, math.floor(self.height / 2) + 1, "Configure to select type", colors.gray)
    end
})
