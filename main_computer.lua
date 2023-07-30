-- main_computer.lua
-- Define the instructions for each turtle
local instructions = {
    north = {
        x = 0,
        z = 25,
        width = 51,
        length = 26,
        depth = 20,
        side = "north"
    },
    south = {
        x = 0,
        z = -25,
        width = 51,
        length = 26,
        depth = 20,
        side = "south"
    },
    east = {
        x = 25,
        z = 0,
        width = 26,
        length = 51,
        depth = 20,
        side = "east"
    },
    west = {
        x = -25,
        z = 0,
        width = 26,
        length = 51,
        depth = 20,
        side = "west"
    }
}

-- Function to write the instructions to a file
function writeInstructions(side, instruction)
    local file = fs.open("instruction_" .. side .. ".txt", "w")
    file.write(textutils.serialize(instruction))
    file.close()
end

-- Write the instructions for each turtle
for side, instruction in pairs(instructions) do
    writeInstructions(side, instruction)
end

-- Function to copy a file to a turtle
function copyToTurtle(side, filename)
    local turtle = peripheral.wrap(side)
    turtle.turnOn()
    sleep(1) -- wait for the turtle to boot up
    fs.copy(filename, "/disk/" .. filename)
    turtle.shutdown()
end

-- Copy the turtle_minion.lua script and the instruction file to each turtle
for side, _ in pairs(instructions) do
    copyToTurtle(side, "turtle_minion.lua")
    copyToTurtle(side, "instruction_" .. side .. ".txt")
end
