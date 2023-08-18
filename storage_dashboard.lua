local DataProcessing = require('data_processing')
local generics = require('generics')

-- Auto-detect the monitor
local monitor = peripheral.wrap(generics.findPeripheralSide('monitor'))

-- Constants
local WIDTH, HEIGHT = monitor.getSize()
local MAX_DATA_POINTS = WIDTH -- Number of data points to store based on monitor width

local storageData = {} -- To store recent storage usage data

-- Function to record the storage usage
local function recordStorageUsage()
    local usedStorage = DataProcessing.fetch_storage_status().usedItemStorage
    table.insert(storageData, usedStorage)

    -- Ensure we don't exceed the maximum data points
    if #storageData > MAX_DATA_POINTS then
        table.remove(storageData, 1)
    end
end

-- Function to calculate the heights for the graph
local function calculateGraphData()
    local heights = {}
    for _, usage in ipairs(storageData) do
        local height = math.floor((usage / DataProcessing.fetch_storage_status().totalItemStorage) * HEIGHT)
        table.insert(heights, height)
    end
    return heights
end

-- Function to draw the storage trend graph
local function drawGraph(heights)
    monitor.clear()

    -- Write Y-axis info
    monitor.setCursorPos(1, 1)
    monitor.write(tostring(DataProcessing.fetch_storage_status().totalItemStorage))
    monitor.setCursorPos(1, HEIGHT)
    monitor.write("0")

    -- Draw each data point based on calculated heights
    for x, height in ipairs(heights) do
        local columnPosition = WIDTH - #heights + x -- Starting from the rightmost position

        monitor.setBackgroundColor(colors.pink)
        for y = HEIGHT, HEIGHT - height + 1, -1 do
            monitor.setCursorPos(columnPosition, y)
            monitor.write(" ")
        end
    end

    -- Reset background color
    monitor.setBackgroundColor(colors.black)
end

-- Main loop to record, calculate, and display the storage trend graph
while true do
    recordStorageUsage()
    local graphData = calculateGraphData()
    drawGraph(graphData)
    sleep(5)
end