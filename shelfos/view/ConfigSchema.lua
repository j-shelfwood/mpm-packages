-- ConfigSchema.lua
-- View configuration schema definitions and validation

local ConfigSchema = {}

-- Field types
ConfigSchema.FieldType = {
    STRING = "string",
    NUMBER = "number",
    BOOLEAN = "boolean",
    SELECT = "select",
    PERIPHERAL = "peripheral"
}

-- Create a string field schema
function ConfigSchema.string(key, label, default, options)
    options = options or {}
    return {
        key = key,
        label = label,
        type = ConfigSchema.FieldType.STRING,
        default = default or "",
        minLength = options.minLength,
        maxLength = options.maxLength,
        pattern = options.pattern
    }
end

-- Create a number field schema
function ConfigSchema.number(key, label, default, options)
    options = options or {}
    return {
        key = key,
        label = label,
        type = ConfigSchema.FieldType.NUMBER,
        default = default or 0,
        min = options.min,
        max = options.max,
        step = options.step or 1,
        largeStep = options.largeStep or 10
    }
end

-- Create a boolean field schema
function ConfigSchema.boolean(key, label, default)
    return {
        key = key,
        label = label,
        type = ConfigSchema.FieldType.BOOLEAN,
        default = default or false
    }
end

-- Create a select field schema
function ConfigSchema.select(key, label, options, default)
    return {
        key = key,
        label = label,
        type = ConfigSchema.FieldType.SELECT,
        options = options or {},  -- Array of {value, label} or strings
        default = default
    }
end

-- Create a peripheral select field schema
function ConfigSchema.peripheral(key, label, peripheralType, default)
    return {
        key = key,
        label = label,
        type = ConfigSchema.FieldType.PERIPHERAL,
        peripheralType = peripheralType,
        default = default
    }
end

-- Validate a value against a field schema
function ConfigSchema.validate(field, value)
    if value == nil then
        return field.default, nil
    end

    if field.type == ConfigSchema.FieldType.STRING then
        value = tostring(value)

        if field.minLength and #value < field.minLength then
            return nil, "Too short (min " .. field.minLength .. ")"
        end

        if field.maxLength and #value > field.maxLength then
            return nil, "Too long (max " .. field.maxLength .. ")"
        end

        if field.pattern and not value:match(field.pattern) then
            return nil, "Invalid format"
        end

        return value, nil

    elseif field.type == ConfigSchema.FieldType.NUMBER then
        value = tonumber(value)

        if not value then
            return nil, "Not a number"
        end

        if field.min and value < field.min then
            return nil, "Too small (min " .. field.min .. ")"
        end

        if field.max and value > field.max then
            return nil, "Too large (max " .. field.max .. ")"
        end

        return value, nil

    elseif field.type == ConfigSchema.FieldType.BOOLEAN then
        if type(value) == "boolean" then
            return value, nil
        end

        if value == "true" or value == 1 then
            return true, nil
        elseif value == "false" or value == 0 then
            return false, nil
        end

        return nil, "Not a boolean"

    elseif field.type == ConfigSchema.FieldType.SELECT then
        -- Check if value is in options
        for _, opt in ipairs(field.options or {}) do
            local optValue = type(opt) == "table" and (opt.value or opt[1]) or opt
            if optValue == value then
                return value, nil
            end
        end

        return nil, "Invalid option"

    elseif field.type == ConfigSchema.FieldType.PERIPHERAL then
        -- Check if peripheral exists
        if peripheral.wrap(value) then
            if field.peripheralType then
                if peripheral.hasType(value, field.peripheralType) then
                    return value, nil
                else
                    return nil, "Wrong peripheral type"
                end
            end
            return value, nil
        end

        return nil, "Peripheral not found"
    end

    return value, nil
end

-- Validate entire config against schema
function ConfigSchema.validateAll(schema, config)
    local validated = {}
    local errors = {}

    for _, field in ipairs(schema) do
        local value = config[field.key]
        local validValue, err = ConfigSchema.validate(field, value)

        if err then
            errors[field.key] = err
            validated[field.key] = field.default
        else
            validated[field.key] = validValue
        end
    end

    return validated, errors
end

-- Get options for a peripheral field
function ConfigSchema.getPeripheralOptions(peripheralType)
    local names = peripheral.getNames()
    local options = {}

    for _, name in ipairs(names) do
        if not peripheralType or peripheral.hasType(name, peripheralType) then
            table.insert(options, {
                value = name,
                label = name
            })
        end
    end

    return options
end

return ConfigSchema
