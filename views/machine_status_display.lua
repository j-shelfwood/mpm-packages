-- machine_status_display.lua
-- Include Data Processing and Grid Display APIs
local wpp = require('wpp')
local GridDisplay = require('grid_display')
local generics = require('generics')

-- Connect to the wireless peripheral network
wpp.wireless.connect("shelfwood")

-- Wrap the monitor
local monitor = peripheral.wrap(generics.findPeripheralSide('monitor'))
local display = GridDisplay.new(monitor)

local function format_callback(item)
    local progressPercentage = string.format("%.1f%%", item.progress * 100)
    local efficiencyInfo = tostring(item.currentEfficiency)
    local craftingInfo = "-"
    local amount = " "
    if item.items and #item.items > 0 then
        craftingInfo = item.items[1].displayName
        amount = item.items[1].count
    elseif item.tanks and #item.tanks > 0 then
        local _, _, fluidName = string.find(item.tanks[1].name, ":(.+)")
        craftingInfo = string.gsub(fluidName, "_", " ")
        amount = item.tanks[1].amount .. 'mB '
    else
        craftingInfo = "No items or fluids found"
    end

    return {
        lines = {progressPercentage .. " | " .. efficiencyInfo, craftingInfo, amount},
        colors = {colors.blue, colors.green, item.isBusy and colors.green or colors.blue}
    }
end

-- Function to fetch machine data
local function fetch_data(machine_type)
    local machine_data = {}
    local peripherals = wpp.peripheral.getNames()
    print("Found " .. #peripherals .. " peripherals on the network.")

    for _, name in ipairs(peripherals) do
        local machine = wpp.peripheral.wrap(name)

        if string.find(name, machine_type) then
            print("Fetching data for " .. name)
            machine.wppPrefetch({"getEnergy", "isBusy", "getEnergyCapacity", "getCraftingInformation", "items"})

            local _, _, name = string.find(name, machine_type .. "_(.+)")
            local craftingInfo = machine.getCraftingInformation() or {}

            local successItems, itemsList = pcall(function()
                return machine.items()
            end)
            local itemsData = successItems and itemsList or nil

            local successTanks, fluidsList = pcall(function()
                return machine.tanks()
            end)
            local tanksData = successTanks and fluidsList or nil

            table.insert(machine_data, {
                name = name,
                energy = machine.getEnergy(),
                capacity = machine.getEnergyCapacity(),
                progress = craftingInfo.progress or 0,
                currentEfficiency = craftingInfo.currentEfficiency or 0,
                items = itemsData,
                tanks = tanksData,
                isBusy = machine.isBusy()
            })
        end
    end

    return machine_data
end

-- Function to refresh the display
local function refresh_display(machine_type)
    local machine_data = fetch_data(machine_type)
    display:display(machine_data, format_callback)
end

-- Get machine type from command line parameter
local args = {...}
local machine_type = args[1] or "modern_industrialization:electrolyzer"

if not machine_type then
    print("Please provide a valid machine type as a command-line parameter.")
    return
end

while true do
    refresh_display(machine_type)
    os.sleep(1)
end
