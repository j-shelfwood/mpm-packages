local ITEMS_PER_PAGE = 10 -- Adjust based on screen size and readability

function safeSerialize(value)
    local seen = {}
    local function _serialize(value)
        if type(value) == "table" then
            if seen[value] then
                return '"[Cyclical table reference]"'
            end
            seen[value] = true
            local serializedTable = {}
            for k, v in pairs(value) do
                table.insert(serializedTable, _serialize(k) .. " = " .. _serialize(v))
            end
            return "{" .. table.concat(serializedTable, ", ") .. "}"
        elseif type(value) == "string" then
            return string.format("%q", value)
        else
            return tostring(value)
        end
    end
    return _serialize(value)
end

function saveToFile(filename, data)
    local file = fs.open(filename, "w")
    if file then
        file.write(data)
        file.close()
        print("Saved to " .. filename)
    else
        print("Failed to save to file.")
    end
end

local Peripherals = mpm('utils/Peripherals')

function inspectPeripheral()
    local peripherals = Peripherals.getNames()
    if #peripherals == 0 then
        print("No peripherals connected.")
        return
    end

    print("Select a peripheral to inspect:")
    for i, peripheralName in ipairs(peripherals) do
        print(i .. ". " .. peripheralName)
    end
    local selection = tonumber(read())
    if selection == nil or selection < 1 or selection > #peripherals then
        print("Invalid selection.")
        return
    end

    local peripheralName = peripherals[selection]
    local methods = Peripherals.getMethods(peripheralName)
    local target = Peripherals.wrap(peripheralName)
    if methods == nil or #methods == 0 then
        print("No methods available for the selected peripheral.")
        return
    end

    print("Methods for the " .. tostring(Peripherals.getType(target)) .. " peripheral:")
    local currentPage = 1
    while true do
        for i = (currentPage - 1) * ITEMS_PER_PAGE + 1, math.min(#methods, currentPage * ITEMS_PER_PAGE) do
            print(i .. ". " .. methods[i])
        end

        print("Page " .. currentPage .. "/" .. math.ceil(#methods / ITEMS_PER_PAGE))
        print("Enter method number (or 'n' for next page, 'p' for previous page):")
        local input = read()

        if input == "n" and currentPage < math.ceil(#methods / ITEMS_PER_PAGE) then
            currentPage = currentPage + 1
        elseif input == "p" and currentPage > 1 then
            currentPage = currentPage - 1
        elseif tonumber(input) and tonumber(input) > 0 and tonumber(input) <= #methods then
            local methodName = methods[tonumber(input)]
            print("Enter arguments for method " .. methodName .. " (comma separated, leave blank for none):")
            local argsInput = read()
            local args = {}
            for arg in string.gmatch(argsInput, "[^,]+") do
                table.insert(args, arg)
            end
            local result = safeSerialize(target[methodName](unpack(args)))
            print("Result:")
            print(result)

            -- Ask the user if they want to save the output
            print("Do you want to save the output to a file? (y/n)")
            local choice = read()
            if choice == "y" then
                local filename = methodName .. ".txt"
                saveToFile(filename, result)
            end
        else
            print("Invalid input. Try again.")
        end
    end
end

inspectPeripheral()
