-- MachineActivityDisplay.lua
-- Displays status of machines of a specific type
-- Shows green when busy, gray when idle

local module

module = {
    sleepTime = 1,

    new = function(monitor, config)
        config = config or {}
        local width, height = monitor.getSize()
        local self = {
            monitor = monitor,
            machine_type = config.machine_type or "modern_industrialization:electrolyzer",
            bar_width = 7,
            bar_height = 4,
            width = width,
            height = height,
            peripherals = {},
            title = "",
            initialized = false
        }

        -- Extract machine type name for display
        local _, _, machineTypeName = string.find(self.machine_type, ":(.+)")

        if not machineTypeName then
            machineTypeName = self.machine_type
        end

        machineTypeName = machineTypeName:gsub("_", " ") -- Replace underscores with spaces
        self.title = string.upper(string.sub(machineTypeName, 1, 1)) .. string.sub(machineTypeName, 2)

        -- Find all peripherals of the specified machine type
        local names = peripheral.getNames()
        for _, name in ipairs(names) do
            if peripheral.getType(name) == self.machine_type then
                table.insert(self.peripherals, peripheral.wrap(name))
            end
        end

        return self
    end,

    mount = function()
        -- Always allow mount - will show empty if no machines found
        return true
    end,

    configure = function()
        print("Enter the machine type (e.g., modern_industrialization:electrolyzer):")
        local machine_type = read()
        return {
            machine_type = machine_type
        }
    end,

    -- Clear a single line by overwriting with spaces
    clearLine = function(self, y)
        self.monitor.setCursorPos(1, y)
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.write(string.rep(" ", self.width))
    end,

    -- Write text at position
    writeAt = function(self, x, y, text)
        self.monitor.setCursorPos(x, y)
        self.monitor.write(text)
    end,

    render = function(self)
        -- One-time initialization
        if not self.initialized then
            self.monitor.clear()
            self.initialized = true
        end

        self.monitor.setTextScale(1)
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)

        module.displayMachineStatus(self)
    end,

    fetchData = function(self)
        local machine_data = {}
        for _, machine in ipairs(self.peripherals) do
            local fullName = peripheral.getName(machine)

            -- Extract short name (number after machine type)
            local _, _, shortName = string.find(fullName, self.machine_type .. "_(.+)")
            shortName = shortName or fullName

            local ok, itemsList = pcall(machine.items)
            if not ok then
                itemsList = {}
            end

            local busyOk, isBusy = pcall(machine.isBusy)
            if not busyOk then
                isBusy = false
            end

            table.insert(machine_data, {
                name = shortName,
                items = itemsList,
                isBusy = isBusy
            })
        end

        return machine_data
    end,

    displayMachineStatus = function(self)
        local machine_data = module.fetchData(self)

        if #machine_data == 0 then
            module.clearLine(self, 1)
            module.writeAt(self, 1, 1, "No machines found")
            module.clearLine(self, 2)
            module.writeAt(self, 1, 2, "Type: " .. self.machine_type)
            -- Clear rest of screen on empty
            for y = 3, self.height do
                module.clearLine(self, y)
            end
            return
        end

        -- Calculate total grid height based on the number of machines
        local columns = math.min(2, #machine_data)
        local rows = math.ceil(#machine_data / columns)
        local totalGridHeight = rows * (self.bar_height + 1) - 1

        -- Display the title at the top (row 2)
        module.clearLine(self, 2)
        local linesUsed = module.displayCenteredTitle(self, 2, self.title)

        -- Adjust the topMargin based on the number of lines used by the title
        local topMargin = math.floor((self.height - totalGridHeight - (2 * linesUsed) - 2) / 2) + linesUsed + 1

        -- Clear the grid area first
        for y = topMargin, math.min(self.height - linesUsed - 1, topMargin + totalGridHeight) do
            module.clearLine(self, y)
        end

        for idx, machine in ipairs(machine_data) do
            local column = (idx - 1) % columns
            local row = math.ceil(idx / columns)
            local x = column * (self.bar_width + 2) + 2
            local y = (row - 1) * (self.bar_height + 1) + topMargin

            -- Draw a colored bar based on isBusy status
            if machine.isBusy then
                self.monitor.setBackgroundColor(colors.green)
            else
                self.monitor.setBackgroundColor(colors.gray)
            end

            for i = 0, self.bar_height - 1 do
                self.monitor.setCursorPos(x, y + i)
                self.monitor.write(string.rep(" ", self.bar_width))
            end

            -- Write the machine number centered in the bar
            self.monitor.setTextColor(colors.black)
            local nameLen = string.len(machine.name or "")
            self.monitor.setCursorPos(x + math.floor((self.bar_width - nameLen) / 2),
                y + math.floor(self.bar_height / 2))
            self.monitor.write(machine.name or "?")
        end

        -- Display the title at the bottom
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.setTextColor(colors.white)
        module.clearLine(self, self.height - linesUsed)
        module.displayCenteredTitle(self, self.height - linesUsed, self.title)
    end,

    displayCenteredTitle = function(self, yPos, title)
        if not title or title == "" then
            return 1
        end

        -- Split title at spaces
        local titleParts = {}
        for part in string.gmatch(title, "%S+") do
            table.insert(titleParts, part)
        end

        if #titleParts == 0 then
            return 1
        end

        local currentTitle = titleParts[1]
        local lineCount = 1

        for i = 2, #titleParts do
            -- Check if adding the next word exceeds the width
            if string.len(currentTitle .. " " .. titleParts[i]) <= self.width then
                currentTitle = currentTitle .. " " .. titleParts[i]
            else
                -- Display the current title and reset for next line
                self.monitor.setCursorPos(math.floor((self.width - string.len(currentTitle)) / 2) + 1, yPos)
                self.monitor.write(currentTitle)
                yPos = yPos + 1
                currentTitle = titleParts[i]
                lineCount = lineCount + 1
            end
        end

        -- Display the last part of the title
        self.monitor.setCursorPos(math.floor((self.width - string.len(currentTitle)) / 2) + 1, yPos)
        self.monitor.write(currentTitle)

        return lineCount
    end
}

return module
