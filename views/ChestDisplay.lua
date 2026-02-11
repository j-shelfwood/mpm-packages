-- ChestDisplay.lua
-- Displays items from all connected inventory peripherals
-- Shows consolidated item counts across all chests

local GridDisplay = mpm('utils/GridDisplay')
local Text = mpm('utils/Text')

local module

module = {
    sleepTime = 1,

    new = function(monitor, config)
        local self = {
            monitor = monitor,
            chests = {},
            display = GridDisplay.new(monitor)
        }

        -- Find all inventory peripherals
        self.chests = module.resolvePeripherals()

        return self
    end,

    mount = function()
        local peripherals = peripheral.getNames()
        for _, name in ipairs(peripherals) do
            if peripheral.hasType(name, "inventory") then
                return true
            end
        end
        return false
    end,

    resolvePeripherals = function()
        local peripherals = peripheral.getNames()
        local chests = {}
        for _, name in ipairs(peripherals) do
            if peripheral.hasType(name, "inventory") then
                local chest = peripheral.wrap(name)
                if chest then
                    table.insert(chests, chest)
                end
            end
        end
        return chests
    end,

    format_callback = function(item)
        return {
            lines = {Text.prettifyItemIdentifier(item.name or "Unknown"), tostring(item.count or 0)},
            colors = {colors.white, colors.white}
        }
    end,

    render = function(self)
        -- Check if any chests are connected
        if #self.chests == 0 then
            -- Try to find chests again
            self.chests = module.resolvePeripherals()

            if #self.chests == 0 then
                self.monitor.clear()
                local width, height = self.monitor.getSize()
                self.monitor.setCursorPos(1, math.floor(height / 2) - 1)
                self.monitor.write("Chest Display")
                self.monitor.setCursorPos(1, math.floor(height / 2) + 1)
                self.monitor.write("No inventories found")
                return
            end
        end

        -- Fetch items with error handling
        local ok, items = pcall(module.fetchItemsFromChests, self)
        if not ok or not items then
            self.monitor.clear()
            self.monitor.setCursorPos(1, 1)
            self.monitor.write("Error fetching items")
            self.monitor.setCursorPos(1, 2)
            self.monitor.write(tostring(items or "unknown"):sub(1, 30))
            return
        end

        -- Handle empty items
        if #items == 0 then
            self.monitor.clear()
            local width, height = self.monitor.getSize()
            self.monitor.setCursorPos(1, math.floor(height / 2) - 1)
            self.monitor.write("Chest Display")
            self.monitor.setCursorPos(1, math.floor(height / 2) + 1)
            self.monitor.write("Inventories are empty")
            self.monitor.setCursorPos(1, math.floor(height / 2) + 2)
            self.monitor.write("(" .. #self.chests .. " connected)")
            return
        end

        -- Sort by count descending
        table.sort(items, function(a, b)
            return (a.count or 0) > (b.count or 0)
        end)

        local displayOk, displayErr = pcall(self.display.display, self.display, items, module.format_callback)
        if not displayOk then
            self.monitor.clear()
            self.monitor.setCursorPos(1, 1)
            self.monitor.write("Display error:")
            self.monitor.setCursorPos(1, 2)
            self.monitor.write(tostring(displayErr):sub(1, 30))
        end
    end,

    fetchItemsFromChests = function(self)
        local allItems = {}

        for _, chest in ipairs(self.chests) do
            local ok, items = pcall(chest.list)
            if ok and items then
                for slot, item in pairs(items) do
                    if item and item.name then
                        table.insert(allItems, {
                            name = item.name,
                            count = item.count or 1,
                            slot = slot
                        })
                    end
                end
            end
        end

        -- Consolidate items by name
        local consolidatedItems = {}
        for _, item in ipairs(allItems) do
            local id = item.name
            if consolidatedItems[id] then
                consolidatedItems[id].count = consolidatedItems[id].count + (item.count or 0)
            else
                consolidatedItems[id] = {
                    name = item.name,
                    count = item.count or 0
                }
            end
        end

        -- Convert to list
        local items = {}
        for _, item in pairs(consolidatedItems) do
            table.insert(items, item)
        end

        return items
    end
}

return module
